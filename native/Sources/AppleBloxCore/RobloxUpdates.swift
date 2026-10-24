import Foundation

public struct RobloxRelease: Codable, Equatable, Sendable {
    public let version: String
    public let clientVersionUpload: String
    public func validated() throws -> RobloxRelease {
        guard clientVersionUpload.hasPrefix("version-"), clientVersionUpload.dropFirst(8).count == 16,
              clientVersionUpload.dropFirst(8).allSatisfy({ $0.isHexDigit && $0.isASCII }),
              !version.isEmpty, version.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else {
            throw FeatureError.message("Roblox returned an invalid release identifier.")
        }
        return self
    }
    public var downloadURL: URL {
        #if arch(arm64)
        URL(string: "https://setup-aws.rbxcdn.com/mac/arm64/\(clientVersionUpload)-RobloxPlayer.zip")!
        #else
        URL(string: "https://setup-aws.rbxcdn.com/mac/\(clientVersionUpload)-RobloxPlayer.zip")!
        #endif
    }
}

public actor RobloxUpdateService {
    public init() {}
    public func latest() async throws -> RobloxRelease {
        var request = URLRequest(url: URL(string: "https://clientsettings.roblox.com/v2/client-version/MacPlayer/channel/LIVE")!)
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FeatureError.message("Roblox’s version service is unavailable.") }
        return try JSONDecoder().decode(RobloxRelease.self, from: data).validated()
    }

    public func download(_ release: RobloxRelease, workspace: URL) async throws -> URL {
        _ = try release.validated()
        let (temporary, response) = try await URLSession.shared.download(from: release.downloadURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FeatureError.message("The Roblox download failed.") }
        try Task.checkCancellation()
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size < 1_073_741_824 else { throw FeatureError.message("The Roblox archive has an unexpected size.") }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let archive = workspace.appendingPathComponent("Roblox.zip")
        try FileManager.default.copyItem(at: temporary, to: archive)
        return try stageArchive(archive, release: release, workspace: workspace)
    }

    func stageArchive(_ archive: URL, release: RobloxRelease, workspace: URL) throws -> URL {
        _ = try release.validated()
        let names = String(decoding: try run("/usr/bin/unzip", ["-Z1", archive.path]), as: UTF8.self)
        try Self.validateArchivePaths(names.split(separator: "\n").map(String.init))
        let listing = String(decoding: try run("/usr/bin/zipinfo", ["-l", archive.path]), as: UTF8.self)
        guard !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw FeatureError.message("This Roblox archive contains symbolic links and cannot be extracted by this installer.")
        }
        let extracted = workspace.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        try Task.checkCancellation()
        let player = extracted.appendingPathComponent("RobloxPlayer.app")
        let app = FileManager.default.fileExists(atPath: player.path) ? player : extracted.appendingPathComponent("Roblox.app")
        let installation = try RobloxInstallation.inspect(app)
        guard installation.version == release.version else { throw FeatureError.message("The downloaded Player version doesn’t match the selected release.") }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=anchor apple generic and certificate leaf[subject.OU] = \"2CFABCH843\"", app.path])
        return app
    }

    public static func validateArchivePaths(_ paths: [String]) throws {
        guard !paths.isEmpty, paths.count < 50_000 else { throw FeatureError.message("Invalid Roblox archive.") }
        for path in paths {
            guard !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains(".."),
                  ["Roblox.app", "RobloxPlayer.app", "__MACOSX"].contains(String(path.split(separator: "/").first ?? "")) else {
                throw FeatureError.message("The Roblox archive contains an unexpected path.")
            }
        }
    }

    public func install(staged app: URL, at destination: URL) throws -> URL? {
        let fm = FileManager.default
        _ = try RobloxInstallation.inspect(app)
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=anchor apple generic and certificate leaf[subject.OU] = \"2CFABCH843\"", app.path])
        guard destination.lastPathComponent == "Roblox.app",
              !destination.pathComponents.contains(where: { $0.hasPrefix(".") }) else { throw FeatureError.message("Choose an Applications folder for Roblox.app.") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".Roblox-install-\(UUID()).app")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: app, to: stage)
        try Task.checkCancellation()
        var backup: URL?
        if fm.fileExists(atPath: destination.path) {
            _ = try RobloxInstallation.inspect(destination)
            let previous = destination.deletingLastPathComponent().appendingPathComponent("Roblox Previous \(UUID().uuidString.prefix(8)).app")
            try fm.moveItem(at: destination, to: previous)
            backup = previous
        }
        do { try fm.moveItem(at: stage, to: destination) }
        catch {
            if let backup { try fm.moveItem(at: backup, to: destination) }
            throw error
        }
        return backup
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FeatureError.message("Roblox validation or extraction failed: \(String(decoding: data.prefix(700), as: UTF8.self))")
        }
        return data
    }
}
