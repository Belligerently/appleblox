import Foundation
import Darwin

/// Persist codes, never the free-form messages displayed in the activity list.
public enum LauncherLogEvent: String, Codable, Sendable {
    case appStarted, activity, playerDetected, playerCountChanged, launchRequested, launchCompleted
    case settingsSaved, profileSaved, profilesImported, modsApplied, accountSaved, sessionJoined
    case engineApplied, engineRestored, modsImported, modsRestored, playerUpdated
    case operationFailed, supportExported
}

public struct SafeLogFailure: Codable, Equatable, Sendable {
    public enum Category: String, Codable, Sendable { case file, network, system, other }
    public let category: Category
    public let code: Int32
    public init(_ error: any Error) {
        let error = error as NSError
        category = switch error.domain {
        case NSCocoaErrorDomain: .file
        case NSURLErrorDomain: .network
        case NSPOSIXErrorDomain: .system
        default: .other
        }
        code = Int32(clamping: error.code)
    }
}

public struct LauncherLogEntry: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let date: Date
    public let event: LauncherLogEvent
    public let count: Int?
    public let failure: SafeLogFailure?
}

public enum SupportFileError: LocalizedError {
    case unsafeFile, invalidLog, destinationExists, archiveFailed
    public var errorDescription: String? {
        switch self {
        case .unsafeFile: "The file or folder is unsafe to use. Existing files have been preserved."
        case .invalidLog: "Saved launcher logs are unreadable or exceed their limits. Existing files have been preserved."
        case .destinationExists: "A file already exists at that location. Choose a new ZIP filename."
        case .archiveFailed: "The support ZIP could not be created. Try another writable folder."
        }
    }
}

/// One atomically replaced journal holds up to four rotated segments (64 KiB each).
/// Only this exact file is managed; unrelated files are never pruned or exported.
public actor LauncherLogStore {
    private struct Journal: Codable {
        var schemaVersion = 1
        var nextSequence: UInt64 = 1
        var segments: [[LauncherLogEntry]] = []
    }
    private let directory: URL
    private let segmentBytes: Int
    private let segmentCount: Int
    private var byteLimit: Int { segmentBytes * segmentCount + 4096 }
    public init(dataDirectory: URL, segmentBytes: Int = 65_536, segmentCount: Int = 4) {
        directory = SupportFiles.canonicalBase(dataDirectory).appendingPathComponent("logs", isDirectory: true)
        self.segmentBytes = segmentBytes
        self.segmentCount = segmentCount
    }

    public func checkedDirectory() throws -> URL {
        guard (512...65_536).contains(segmentBytes), (1...8).contains(segmentCount) else { throw SupportFileError.invalidLog }
        try SupportFiles.prepareDirectory(directory)
        return directory
    }

    private func read() throws -> (Journal, Data?) {
        let file = try checkedDirectory().appendingPathComponent("launcher-log.json")
        guard let bytes = try SupportFiles.readRegular(file, limit: byteLimit) else { return (Journal(), nil) }
        do {
            // Reject unknown fields instead of silently discarding them on the next write.
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  Set(object.keys) == ["schemaVersion", "nextSequence", "segments"],
                  let segments = object["segments"] as? [[[String: Any]]],
                  segments.allSatisfy({ $0.allSatisfy { entry in
                      Set(entry.keys).isSubset(of: ["sequence", "date", "event", "count", "failure"]) &&
                      (entry["failure"] == nil || (entry["failure"] as? [String: Any]).map { Set($0.keys) == ["category", "code"] } == true)
                  } }) else { throw SupportFileError.invalidLog }
            let journal = try JSONDecoder().decode(Journal.self, from: bytes)
            guard journal.schemaVersion == 1, journal.nextSequence > 0,
                  journal.segments.count <= segmentCount,
                  journal.segments.allSatisfy({ !$0.isEmpty && (try? JSONEncoder().encode($0).count).map { $0 <= segmentBytes } == true }) else { throw SupportFileError.invalidLog }
            let entries = journal.segments.flatMap { $0 }
            var prior: UInt64?
            for entry in entries {
                guard entry.sequence > 0, entry.sequence < UInt64.max,
                      entry.date.timeIntervalSince1970.isFinite,
                      (0...253402300799).contains(entry.date.timeIntervalSince1970),
                      entry.count.map({ (0...10_000).contains($0) }) ?? true,
                      prior.map({ entry.sequence == $0 + 1 }) ?? true else { throw SupportFileError.invalidLog }
                prior = entry.sequence
            }
            guard prior.map({ journal.nextSequence == $0 + 1 }) ?? (journal.nextSequence == 1) else { throw SupportFileError.invalidLog }
            return (journal, bytes)
        } catch { throw SupportFileError.invalidLog }
    }

    public func append(_ event: LauncherLogEvent, count: Int? = nil, failure: SafeLogFailure? = nil, date: Date = Date()) throws {
        var (journal, original) = try read()
        guard journal.nextSequence < UInt64.max, date.timeIntervalSince1970.isFinite,
              (0...253402300799).contains(date.timeIntervalSince1970) else { throw SupportFileError.invalidLog }
        let entry = LauncherLogEntry(sequence: journal.nextSequence, date: date, event: event,
                                     count: count.map { min(10_000, max(0, $0)) }, failure: failure)
        if journal.segments.isEmpty { journal.segments = [[]] }
        let index = journal.segments.count - 1
        if try JSONEncoder().encode(journal.segments[index] + [entry]).count > segmentBytes {
            journal.segments.append([entry])
        } else { journal.segments[index].append(entry) }
        if journal.segments.count > segmentCount { journal.segments.removeFirst(journal.segments.count - segmentCount) }
        journal.nextSequence += 1
        let bytes = try JSONEncoder().encode(journal)
        guard bytes.count <= byteLimit else { throw SupportFileError.invalidLog }
        let file = directory.appendingPathComponent("launcher-log.json")
        let stage = directory.appendingPathComponent(".launcher-log-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try SupportFiles.writePrivate(bytes, to: stage)
        guard try SupportFiles.readRegular(file, limit: byteLimit) == original else { throw SupportFileError.unsafeFile }
        if original == nil {
            try FileManager.default.linkItem(at: stage, to: file)
        } else {
            guard Darwin.rename(stage.path, file.path) == 0 else { throw SupportFileError.unsafeFile }
        }
    }

    public func snapshot() throws -> [LauncherLogEntry] { try read().0.segments.flatMap { $0 } }
}

// Shared file boundaries for the two actor services. No shell, recursive scans or arbitrary input filenames.
enum SupportFiles {
    // Foundation deliberately retains /var and /tmp aliases on macOS; realpath resolves them.
    // Resolve only the caller-selected base, never our managed logs child or journal.
    static func canonicalBase(_ url: URL) -> URL {
        var existing = url
        var missing: [String] = []
        while true {
            if let path = Darwin.realpath(existing.path, nil) {
                defer { free(path) }
                var resolved = URL(fileURLWithPath: String(cString: path), isDirectory: true)
                for component in missing.reversed() { resolved.appendPathComponent(component, isDirectory: true) }
                return resolved
            }
            guard existing.path != "/" else { return url }
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
    }

    static func prepareDirectory(_ url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if parent != url { try validateAncestors(parent) }
        if let attributes = try? fm.attributesOfItem(atPath: url.path) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw SupportFileError.unsafeFile }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try validateAncestors(url)
    }
    static func validateAncestors(_ url: URL) throws {
        var current = url
        while current.path != "/" {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: current.path) {
                guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw SupportFileError.unsafeFile }
            }
            current.deleteLastPathComponent()
        }
    }
    static func readRegular(_ url: URL, limit: Int) throws -> Data? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else {
            // A dangling symlink still has attributes; inaccessible files must not be mistaken for missing ones.
            if fm.fileExists(atPath: url.path) { throw SupportFileError.unsafeFile }
            return nil
        }
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.referenceCount] as? NSNumber)?.intValue == 1,
              let size = (attrs[.size] as? NSNumber)?.intValue, size <= limit else { throw SupportFileError.unsafeFile }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw SupportFileError.unsafeFile }
        return data
    }
    static func writePrivate(_ bytes: Data, to url: URL) throws {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw SupportFileError.unsafeFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: bytes)
    }
}
