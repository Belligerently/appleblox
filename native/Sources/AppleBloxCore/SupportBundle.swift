import Foundation

/// Deliberately separate from Codable configuration: no records, arbitrary strings, credentials or paths.
public struct SupportSettingsSummary: Encodable, Sendable {
    let theme: AppTheme
    let preferences: [String: Bool]
    public init(configuration: NativeConfiguration) {
        theme = configuration.appearance.theme
        let f = configuration.features
        preferences = [
            "reduceMotion": configuration.appearance.reduceMotion,
            "reduceTransparency": configuration.appearance.reduceTransparency,
            "showGameArtwork": configuration.appearance.showGameArtwork,
            "applyEngineOnLaunch": configuration.engine.applyOnLaunch,
            "applyModsOnLaunch": f.applyModsOnLaunch, "legacyResolution": f.legacyResolution,
            "bloxstrapSDK": f.bloxstrapSDK, "gameControlledPresence": f.gameControlledPresence,
            "discordPresence": f.discordPresence, "discordPlayTime": f.discordPlayTime,
            "discordGameActivity": f.discordGameActivity, "discordArtwork": f.discordArtwork,
            "discordGameButton": f.discordGameButton, "serverLocation": f.serverLocation,
            "serverJoinedNotifications": f.serverJoinedNotifications, "notificationSounds": f.notificationSounds,
            "trackHistory": f.trackHistory, "checkUpdatesOnOpen": f.checkUpdatesOnOpen,
            "automaticUpdates": f.automaticUpdates, "newPlayerInstance": f.newPlayerInstance,
            "experimentalFPSWorkaround": f.experimentalFPSWorkaround, "quitAfterGame": f.quitAfterGame,
            "quitLauncherWithPlayer": f.quitLauncherWithPlayer, "returnToWebsite": f.returnToWebsite
        ]
    }
}

public struct SupportBundleFile: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let text: String
    fileprivate init(_ name: String, _ text: String) { self.name = name; self.text = text }
}

/// Immutable snapshot: the ZIP is built from these exact reviewed contents, never from a directory scan.
public struct SupportBundleDraft: Identifiable, Sendable {
    public let id = UUID()
    private let diagnostics: String
    private let settings: String?
    private let logs: String?
    public var hasLogs: Bool { logs != nil }
    public init(report: DiagnosticsReport, settings: SupportSettingsSummary?, logs: [LauncherLogEntry]?) throws {
        diagnostics = report.text
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.settings = try settings.map { String(decoding: try encoder.encode($0), as: UTF8.self) + "\n" }
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.logs = try logs.map { entries in
            try entries.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        }
    }
    public func files(includeLogs: Bool) -> [SupportBundleFile] {
        var result = [SupportBundleFile("README.txt", """
        AppleBlox Native support bundle
        This is a local troubleshooting snapshot, not a settings backup. Nothing is uploaded automatically.
        Includes: fixed-field diagnostics and a preference summary when settings are readable.
        Launcher events: \(includeLogs && hasLogs ? "included (timestamps, codes, counts and numeric errors only)" : "omitted").
        Settings summary: \(settings == nil ? "omitted because settings were unreadable" : "included (fixed preferences only)").
        Saved launcher logs: \(hasLogs ? "readable" : "unavailable; existing files were preserved").
        Excludes: account records, cookies, Keychain, names, IDs, paths, URLs, raw activity/Roblox logs,
        engine flag values, custom themes, mods, backups and full configuration files.
        The review screen displays the exact uncompressed file contents saved in this ZIP.
        \n
        """), SupportBundleFile("diagnostics.txt", diagnostics)]
        if let settings { result.append(SupportBundleFile("settings-summary.json", settings)) }
        if includeLogs, let logs { result.append(SupportBundleFile("launcher-events.jsonl", logs)) }
        return result
    }
}

public actor SupportBundleExporter {
    public typealias Archiver = @Sendable (_ directory: URL, _ archive: URL, _ names: [String]) throws -> Void
    private let archiver: Archiver
    public init(archiver: @escaping Archiver = SupportBundleExporter.zip) { self.archiver = archiver }

    public func save(_ draft: SupportBundleDraft, includeLogs: Bool, to destination: URL) throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == "zip" else { throw SupportFileError.archiveFailed }
        let parent = SupportFiles.canonicalBase(destination.deletingLastPathComponent())
        try SupportFiles.validateAncestors(parent)
        let target = parent.appendingPathComponent(destination.lastPathComponent)
        if (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil { throw SupportFileError.destinationExists }
        let stage = parent.appendingPathComponent(".appleblox-support-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        let files = draft.files(includeLogs: includeLogs)
        guard files.reduce(0, { $0 + $1.text.utf8.count }) <= 1_048_576 else { throw SupportFileError.archiveFailed }
        for file in files { try SupportFiles.writePrivate(Data(file.text.utf8), to: stage.appendingPathComponent(file.name)) }
        let archive = stage.appendingPathComponent("bundle.zip")
        try archiver(stage, archive, files.map(\.name))
        guard let bytes = try SupportFiles.readRegular(archive, limit: 1_100_000), !bytes.isEmpty else { throw SupportFileError.archiveFailed }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        do { try FileManager.default.linkItem(at: archive, to: target) }
        catch {
            if (try? FileManager.default.attributesOfItem(atPath: target.path)) != nil { throw SupportFileError.destinationExists }
            throw SupportFileError.archiveFailed
        }
    }

    public static func zip(directory: URL, archive: URL, names: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C"]
        process.standardInput = FileHandle.nullDevice
        process.currentDirectoryURL = directory
        process.arguments = ["-X", "-q", "-0", archive.path] + names
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw SupportFileError.archiveFailed }
    }
}
