import Foundation

public struct DiscordPresenceOptions: Equatable, Sendable {
    public var showGameActivity: Bool
    public var showPlayTime: Bool
    public var showArtwork: Bool
    public var showGameButton: Bool

    public init(showGameActivity: Bool = true, showPlayTime: Bool = true, showArtwork: Bool = false, showGameButton: Bool = true) {
        self.showGameActivity = showGameActivity
        self.showPlayTime = showPlayTime
        self.showArtwork = showArtwork
        self.showGameButton = showGameButton
    }
}

/// Exactly the public fields sent to Discord, without account, server, or launch-token data.
public struct DiscordActivity: Encodable, Equatable, Sendable {
    public struct Timestamps: Encodable, Equatable, Sendable { public let start: Int64 }
    public struct Assets: Encodable, Equatable, Sendable {
        public let largeImage: String
        public let largeText: String
        private enum CodingKeys: String, CodingKey { case largeImage = "large_image", largeText = "large_text" }
    }
    public struct Button: Encodable, Equatable, Sendable { public let label: String; public let url: String }
    public let details: String
    public let state: String
    public let timestamps: Timestamps?
    public let assets: Assets?
    public let buttons: [Button]?

    public init(session: PlaySession?, game: GameDetails? = nil, options: DiscordPresenceOptions = .init()) {
        // Reject stale metadata and malformed place IDs rather than publishing a different game's identity.
        let placeID = session.flatMap { try? GameShortcut(name: "Game", placeID: $0.placeID).placeID }
        let metadata = game.flatMap { $0.isValid && $0.placeID == placeID ? $0 : nil }
        let revealGame = options.showGameActivity && session != nil && placeID != nil
        details = revealGame ? Self.text(session?.name ?? "", fallback: "Playing Roblox") : (session == nil ? "Browsing Roblox" : "Playing Roblox")
        if revealGame, options.showArtwork, let creator = metadata?.creator.trimmingCharacters(in: .whitespacesAndNewlines), !creator.isEmpty {
            state = Self.text("by " + creator, fallback: "Playing with AppleBlox Native")
        } else { state = "Playing with AppleBlox Native" }

        if options.showPlayTime, let session,
           let start = Int64(exactly: session.startedAt.timeIntervalSince1970.rounded(.down)), start >= 0 {
            timestamps = Timestamps(start: start)
        } else { timestamps = nil }

        if revealGame, options.showArtwork, let metadata,
           let icon = GameDetails.permittedIcon(metadata.iconURL), icon.absoluteString.utf8.count <= 1024 {
            assets = Assets(largeImage: icon.absoluteString, largeText: Self.text(metadata.name, fallback: "Roblox"))
        } else { assets = nil }

        if revealGame, options.showGameButton, let placeID {
            buttons = [Button(label: "View game", url: "https://www.roblox.com/games/\(placeID)/")]
        } else { buttons = nil }
    }

    private static func text(_ value: String, fallback: String) -> String {
        let cleaned = value.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = String(cleaned.unicodeScalars.prefix(128))
        return result.unicodeScalars.count >= 2 ? result : fallback
    }
}
