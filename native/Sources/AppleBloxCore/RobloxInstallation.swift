import Foundation

public struct RobloxInstallation: Equatable, Sendable {
    public static let bundleIdentifier = "com.roblox.RobloxPlayer"
    public let url: URL
    public let version: String

    public static func inspect(_ url: URL) throws -> RobloxInstallation {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app" else { throw InstallationError.invalidBundle }
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard plist?["CFBundleIdentifier"] as? String == bundleIdentifier,
              plist?["CFBundlePackageType"] as? String == "APPL",
              let executable = plist?["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != "..",
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(executable)").path)
        else { throw InstallationError.invalidBundle }
        return RobloxInstallation(url: url, version: plist?["CFBundleShortVersionString"] as? String ?? "Unknown")
    }

    public func contentsDirectory() throws -> URL {
        let verified = try Self.inspect(url)
        let directory = verified.url.appendingPathComponent("Contents", isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL else {
            throw InstallationError.unsafeContents
        }
        return directory
    }

    public static func discover(candidates: [URL]) -> [RobloxInstallation] {
        var seen = Set<String>()
        return candidates.compactMap { try? inspect($0) }.filter { seen.insert($0.url.path).inserted }
    }
}

public enum InstallationError: LocalizedError {
    case invalidBundle, missingInstallation, unsafeContents

    public var errorDescription: String? {
        switch self {
        case .invalidBundle: "Choose the Roblox Player application. This bundle is missing its Player identifier or executable."
        case .unsafeContents: "Player’s Contents folder is missing or points outside the app. Choose a valid Player installation again."
        case .missingInstallation: "Choose a Roblox installation before launching."
        }
    }
}
