import Foundation
import Darwin

/// Portable preferences, not an account/session or resource archive.
public struct SettingsBackupDocument: Codable, Sendable {
    public let format: String
    public let version: Int
    public let configuration: NativeConfiguration

    public init(configuration: NativeConfiguration) throws {
        format = "appleblox-native-settings"
        version = 1
        var portable = try configuration.validated()
        portable.customRobloxPath = nil
        portable.features.accounts = []
        portable.features.selectedAccountID = nil
        portable.features.mods = []
        portable.features.applyModsOnLaunch = false
        self.configuration = portable
    }
    public func validated() throws -> Self {
        guard format == "appleblox-native-settings", version == 1,
              configuration.customRobloxPath == nil, configuration.features.accounts.isEmpty,
              configuration.features.selectedAccountID == nil, configuration.features.mods.isEmpty,
              configuration.shortcuts.count <= 1000, configuration.engine.profiles.count <= 128,
              configuration.shortcuts.allSatisfy({ $0.name.count <= 300 }) else { throw SettingsBackupError.invalid }
        _ = try configuration.validated()
        return self
    }
    public var data: Data {
        get throws {
            _ = try validated()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let bytes = try encoder.encode(self)
            guard bytes.count <= SettingsBackupService.limit else { throw SettingsBackupError.invalid }
            return bytes
        }
    }
}
public enum SettingsBackupError: LocalizedError {
    case invalid, changed, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalid: "Choose an AppleBlox Native settings backup up to 8 MiB. Its format or settings are invalid."
        case .changed: "Settings changed after review. Cancel and review the backup again."
        case .unavailable: "The settings backup could not be saved safely. Existing files were preserved."
        }
    }
}
public struct SettingsRestorePlan: Sendable {
    public let document: SettingsBackupDocument
    public let restored: NativeConfiguration
    fileprivate let original: Data?
    fileprivate let baseline: NativeConfiguration
}
public struct SettingsBackupReview: Identifiable, Sendable {
    public let id = UUID()
    public let document: SettingsBackupDocument
    public let restore: SettingsRestorePlan?
    public init(document: SettingsBackupDocument, restore: SettingsRestorePlan? = nil) {
        self.document = document; self.restore = restore
    }
}

/// All disk operations are serialized off the UI actor. Imports never extract archives or follow links.
public actor SettingsBackupService {
    public static let limit = 8_388_608
    private let directory: URL
    private var settings: URL { directory.appendingPathComponent("native-settings.json") }
    public init(directory: URL) {
        self.directory = SupportFiles.canonicalBase(directory.deletingLastPathComponent()).appendingPathComponent(directory.lastPathComponent, isDirectory: true)
    }

    public func export(_ document: SettingsBackupDocument, to destination: URL) throws {
        guard destination.isFileURL else { throw SettingsBackupError.unavailable }
        let target = SupportFiles.canonicalBase(destination.deletingLastPathComponent()).appendingPathComponent(destination.lastPathComponent)
        try SupportFiles.validateAncestors(target.deletingLastPathComponent())
        let stage = target.deletingLastPathComponent().appendingPathComponent(".settings-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try SupportFiles.writePrivate(document.data, to: stage)
        // Hard-link creation refuses an existing file, even if it appeared after the save panel.
        do { try FileManager.default.linkItem(at: stage, to: target) }
        catch { throw SettingsBackupError.unavailable }
    }
    public func prepare(from source: URL, current: NativeConfiguration) throws -> SettingsRestorePlan {
        guard source.isFileURL, let bytes = try SupportFiles.readRegular(source, limit: Self.limit) else { throw SettingsBackupError.invalid }
        let document: SettingsBackupDocument
        do { document = try JSONDecoder().decode(SettingsBackupDocument.self, from: bytes).validated() }
        catch { throw SettingsBackupError.invalid }
        try SupportFiles.validateAncestors(directory)
        let original = try SupportFiles.readRegular(settings, limit: Self.limit)
        if let original {
            // Older files may omit profiles and generate their default IDs when decoded.
            // Validate the disk snapshot, then guard its exact bytes again at commit.
            _ = try JSONDecoder().decode(NativeConfiguration.self, from: original).validated()
        }
        var next = document.configuration
        // Keep machine-local resources and login selection. Imported automation always starts off.
        next.customRobloxPath = current.customRobloxPath
        next.features.mods = current.features.mods
        next.features.accounts = current.features.accounts
        next.features.selectedAccountID = current.features.selectedAccountID
        next.engine.applyOnLaunch = false
        next.features.applyModsOnLaunch = false
        next.features.experimentalFPSWorkaround = false
        next.features.discordPresence = false
        next.features.bloxstrapSDK = false
        next.features.gameControlledPresence = false
        next.features.serverLocation = false
        next.features.serverJoinedNotifications = false
        next.features.trackHistory = false
        next.features.checkUpdatesOnOpen = false
        next.features.automaticUpdates = false
        next.features.quitAfterGame = false
        next.features.quitLauncherWithPlayer = false
        next.features.returnToWebsite = false
        return SettingsRestorePlan(document: document, restored: try next.validated(), original: original, baseline: current)
    }
    /// Save the previous configuration before atomically installing the reviewed settings.
    public func restore(_ plan: SettingsRestorePlan, current: NativeConfiguration) throws -> URL {
        guard current == plan.baseline else { throw SettingsBackupError.changed }
        try SupportFiles.prepareDirectory(directory)
        guard try SupportFiles.readRegular(settings, limit: Self.limit) == plan.original else { throw SettingsBackupError.changed }
        let recovery = directory.appendingPathComponent("settings-recovery", isDirectory: true)
        try SupportFiles.prepareDirectory(recovery)
        let saved = recovery.appendingPathComponent("before-restore-\(UUID()).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SupportFiles.writePrivate(try plan.original ?? encoder.encode(current), to: saved)
        let stage = directory.appendingPathComponent(".settings-restore-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try SupportFiles.writePrivate(try encoder.encode(plan.restored.validated()), to: stage)
        guard try SupportFiles.readRegular(settings, limit: Self.limit) == plan.original else { throw SettingsBackupError.changed }
        if plan.original == nil { try FileManager.default.linkItem(at: stage, to: settings) }
        else if Darwin.rename(stage.path, settings.path) != 0 { throw SettingsBackupError.unavailable }
        return saved
    }
}
