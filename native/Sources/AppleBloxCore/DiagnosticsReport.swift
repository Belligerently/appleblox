import Foundation

/// A fixed-field support report. Never accepts configuration records, paths, or activity messages.
public struct DiagnosticsReport: Sendable {
    public var appVersion = "Development"
    public var appBuild = "Unknown"
    public var systemVersion = ProcessInfo.processInfo.operatingSystemVersion
    public var architecture = "unknown"
    public var playerVersion: String?
    public var playerRunning = false
    public var settingsReadable = true
    public var gameCount = 0
    public var profileCount = 0
    public var modCount = 0
    public var metadataCount = 0
    public var hasEngineBackup = false
    public var hasModBackup = false
    public init() {}

    public var text: String {
        let version = Self.version(appVersion) ?? "Development"
        let build = appBuild.count <= 20 && !appBuild.isEmpty && appBuild.allSatisfy({ $0.isASCII && $0.isNumber }) ? appBuild : "Unknown"
        let architecture = ["arm64", "x86_64"].contains(architecture) ? architecture : "unknown"
        return """
        AppleBlox Native diagnostics
        App: \(version) (\(build))
        macOS: \(max(0, systemVersion.majorVersion)).\(max(0, systemVersion.minorVersion)).\(max(0, systemVersion.patchVersion))
        Architecture: \(architecture)
        Player version: \(playerVersion.flatMap(Self.version) ?? "Not detected")
        Player running: \(playerRunning ? "yes" : "no")
        Settings readable: \(settingsReadable ? "yes" : "no")
        Saved games: \(max(0, gameCount))
        Engine profiles: \(max(0, profileCount))
        Mod packs: \(max(0, modCount))
        Cached game details: \(max(0, metadataCount))
        Engine backup available: \(hasEngineBackup ? "yes" : "no")
        Resource backup available: \(hasModBackup ? "yes" : "no")

        Excludes account data, game/profile names, local paths, URLs, raw logs, and activity messages.
        """
    }

    private static func version(_ text: String) -> String? {
        guard text.count <= 80, text.range(of: #"\A[0-9]+(?:\.[0-9]+){1,3}(?:-dev\.[0-9]+)?\z"#, options: .regularExpression) != nil else { return nil }
        return text
    }
}
