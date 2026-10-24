import CryptoKit
import Foundation

/// Serializes apply/restore operations and keeps file I/O away from the UI actor.
public actor ClientSettingsStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private struct Backup: Codable {
        let version: Int
        let installationPath: String
        let createdAt: Date
        let original: Data?
        var lastWritten: Data?
    }

    public func hasBackup(for installation: RobloxInstallation) -> Bool {
        FileManager.default.fileExists(atPath: backupURL(for: installation).path)
    }

    public func archiveBackup(for installation: RobloxInstallation) throws {
        let source = backupURL(for: installation)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let archive = directory.appendingPathComponent("previous-installations", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: archive.appendingPathComponent("\(UUID()).json"))
    }

    public func apply(_ flags: [String: FlagValue], to installation: RobloxInstallation) throws {
        let data = Data(try FastFlags.json(flags).utf8)
        let installation = try RobloxInstallation.inspect(installation.url)
        let target = try targetURL(for: installation)
        let current = try readIfPresent(target)
        let file = backupURL(for: installation)
        let previousBackup: Data?
        var backup: Backup
        if let existing = try readIfPresent(file, limit: 4_194_304) {
            previousBackup = existing
            backup = try decodeBackup(existing, for: installation)
            guard current == backup.lastWritten else { throw EngineError.changedSettings }
        } else {
            previousBackup = nil
            backup = Backup(version: 1, installationPath: installation.url.path, createdAt: Date(), original: current, lastWritten: current)
            // The exact original bytes (including invalid JSON) are durable before editing Player settings.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(backup).write(to: file, options: .atomic)
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        backup.lastWritten = data
        do {
            try JSONEncoder().encode(backup).write(to: file, options: .atomic)
        } catch {
            // A failed backup update must not leave settings that cannot be restored.
            try restoreBytes(current, at: target)
            if let previousBackup { try previousBackup.write(to: file, options: .atomic) }
            throw error
        }
    }

    public func restore(_ installation: RobloxInstallation) throws {
        let installation = try RobloxInstallation.inspect(installation.url)
        let target = try targetURL(for: installation)
        let file = backupURL(for: installation)
        guard let data = try readIfPresent(file, limit: 4_194_304) else { throw EngineError.noBackup }
        let backup = try decodeBackup(data, for: installation)
        let current = try readIfPresent(target)
        // Also permits retry after a successful restore whose backup cleanup failed.
        guard current == backup.lastWritten || current == backup.original else { throw EngineError.changedSettings }
        try restoreBytes(backup.original, at: target)
        try FileManager.default.removeItem(at: file)
    }

    private func backupURL(for installation: RobloxInstallation) -> URL {
        let key = SHA256.hash(data: Data(installation.url.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(key).json")
    }

    private func decodeBackup(_ data: Data, for installation: RobloxInstallation) throws -> Backup {
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data), backup.version == 1,
              backup.installationPath == installation.url.path else { throw EngineError.invalidBackup }
        return backup
    }

    private func targetURL(for installation: RobloxInstallation) throws -> URL {
        var url = installation.url
        for (component, isDirectory) in [("Contents", true), ("MacOS", true), ("ClientSettings", true), ("ClientAppSettings.json", false)] {
            url.appendPathComponent(component)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let expected: FileAttributeType = isDirectory ? .typeDirectory : .typeRegular
                guard attributes[.type] as? FileAttributeType == expected else { throw EngineError.unsafePath }
            }
        }
        return url
    }

    private func readIfPresent(_ url: URL, limit: Int = 1_048_576) throws -> Data? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw EngineError.unsafePath }
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= limit else { throw EngineError.fileTooLarge }
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func restoreBytes(_ data: Data?, at url: URL) throws {
        if let data {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
