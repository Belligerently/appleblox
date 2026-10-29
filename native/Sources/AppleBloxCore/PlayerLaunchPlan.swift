import Foundation

/// Launch Services arguments are passed as an array, without a shell or persistent bundle edits.
public struct PlayerLaunchPlan: Equatable, Sendable {
    public let arguments: [String]
    public let urlToOpen: URL?
    public let createsNewInstance: Bool

    public init(url: URL? = nil, legacyResolution: Bool, newInstance: Bool, playerRunning: Bool) throws {
        let launchURL = try url.map { try LaunchLink($0).url }
        if legacyResolution, playerRunning, !newInstance {
            throw FeatureError.message("Legacy Resolution needs a fresh Player instance. Quit Roblox first, or enable Request a new Player instance in Integrations.")
        }
        createsNewInstance = newInstance
        if legacyResolution {
            arguments = ["-AppleMagnifiedMode", "YES"] + (launchURL.map { [$0.absoluteString] } ?? [])
            urlToOpen = nil
        } else {
            arguments = []
            urlToOpen = launchURL
        }
    }
}
