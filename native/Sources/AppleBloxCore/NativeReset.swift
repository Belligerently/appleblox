import Foundation

public struct NativeResetPlan: Identifiable, Sendable {
    public let id = UUID()
    public let recoveryDirectory: URL
    public let itemNames: [String]
    public let gameCount: Int
    public let profileCount: Int
    public let accountCount: Int
    public let modCount: Int
    fileprivate let configuration: Data?
    fileprivate let rootID: UInt64
}
public enum NativeResetError: LocalizedError {
    case unsafeDirectory, changed, busy, rollback(URL)
    public var errorDescription: String? {
        switch self {
        case .unsafeDirectory: "Reset only supports the native data folder with recognized files. Unexpected files, unsafe links or unreadable settings were preserved."
        case .changed: "Native settings or folder contents changed after review. Cancel and review reset again."
        case .busy: "A reset is already in progress."
        case .rollback(let url): "Reset stopped. Data remains in the recovery folder at \(url.path). Leave the app closed until the data folder is recovered."
        }
    }
}

/// Reset archives the whole native store on the same volume. Player files and original backups are never deleted.
public actor NativeResetService {
    private let directory: URL
    private var resetting = false
    private static let known: Set<String> = ["native-settings.json", "game-details-cache.json", "play-history.json", "mods", "engine-backups", "logs", "launcher-icons", "native-themes", "settings-recovery", "history-recovery", ".DS_Store"]
    public init(dataDirectory: URL) {
        directory = SupportFiles.canonicalBase(dataDirectory.deletingLastPathComponent()).appendingPathComponent(dataDirectory.lastPathComponent, isDirectory: true)
    }
    public func prepare() throws -> NativeResetPlan {
        try SupportFiles.validateAncestors(directory)
        guard directory.pathComponents.count > 2,
              let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let rootID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { throw NativeResetError.unsafeDirectory }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        guard !names.isEmpty, Set(names).isSubset(of: Self.known) else { throw NativeResetError.unsafeDirectory }
        let bytes = try SupportFiles.readRegular(directory.appendingPathComponent("native-settings.json"), limit: 8_388_608)
        let config: NativeConfiguration
        if let bytes { config = try JSONDecoder().decode(NativeConfiguration.self, from: bytes).validated() }
        else { config = NativeConfiguration() }
        let parent = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + " Recovery", isDirectory: true)
        let recovery = parent.appendingPathComponent("reset-\(UUID())", isDirectory: true)
        return NativeResetPlan(recoveryDirectory: recovery, itemNames: names, gameCount: config.shortcuts.count,
            profileCount: config.engine.profiles.count, accountCount: config.features.accounts.count,
            modCount: config.features.mods.count, configuration: bytes, rootID: rootID)
    }
    public func commit(_ review: NativeResetPlan, clearCredentials: @Sendable () async throws -> Void) async throws -> URL {
        guard !resetting else { throw NativeResetError.busy }
        resetting = true
        defer { resetting = false }
        let current = try prepare()
        guard current.rootID == review.rootID, current.configuration == review.configuration,
              current.itemNames == review.itemNames else { throw NativeResetError.changed }
        let parent = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + " Recovery", isDirectory: true)
        guard review.recoveryDirectory.deletingLastPathComponent() == parent,
              review.recoveryDirectory.lastPathComponent.hasPrefix("reset-") else { throw NativeResetError.unsafeDirectory }
        try SupportFiles.prepareDirectory(parent)
        let recovery = review.recoveryDirectory
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let archived = recovery.appendingPathComponent("data", isDirectory: true)
        do {
            try FileManager.default.moveItem(at: directory, to: archived)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: archived.path)
            let readme = """
            AppleBlox Native reset recovery
            All old native files are in data/. Engine and resource backups remain there.
            Reset did not restore or change Roblox Player files, its installed app or its login.
            Launcher Keychain sessions are removed only after this archive is created.
            Account passwords/cookies are not stored in this archive and cannot be recovered here.
            To recover old settings/backups: quit AppleBlox, move any fresh native data folder aside,
            then move this data folder back to: \(directory.path)
            Restored saved-account records need a new sign-in after credentials have been cleared.
            Do not merge old and fresh backup folders or delete this archive before restoring Player changes.
            """
            try SupportFiles.writePrivate(Data(readme.utf8), to: recovery.appendingPathComponent("RECOVERY.txt"))
            try await clearCredentials()
            return recovery
        } catch {
            if FileManager.default.fileExists(atPath: archived.path) {
                do { try FileManager.default.moveItem(at: archived, to: directory) }
                catch { throw NativeResetError.rollback(recovery) }
            }
            try? FileManager.default.removeItem(at: recovery)
            throw error
        }
    }
}
