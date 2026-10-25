import Foundation

public struct DiscordPresenceOptions: Equatable, Sendable {
    public var allowGameControl: Bool
    public var showGameActivity: Bool
    public var showPlayTime: Bool
    public var showArtwork: Bool
    public var showGameButton: Bool

    public init(showGameActivity: Bool = true, showPlayTime: Bool = true, showArtwork: Bool = false, showGameButton: Bool = true, allowGameControl: Bool = false) {
        self.allowGameControl = allowGameControl
        self.showGameActivity = showGameActivity
        self.showPlayTime = showPlayTime
        self.showArtwork = showArtwork
        self.showGameButton = showGameButton
    }
}

/// Supported Discord activity fields. Opt-in SDK text cannot add launch data or invite links.
public struct DiscordActivity: Encodable, Equatable, Sendable {
    public struct Timestamps: Encodable, Equatable, Sendable {
        public let start: Int64?
        public let end: Int64?
        init(start: Int64? = nil, end: Int64? = nil) { self.start = start; self.end = end }
    }
    public struct Assets: Encodable, Equatable, Sendable {
        public let largeImage: String?
        public let largeText: String?
        public let smallImage: String?
        public let smallText: String?
        init(largeImage: String? = nil, largeText: String? = nil, smallImage: String? = nil, smallText: String? = nil) {
            self.largeImage = largeImage; self.largeText = largeText; self.smallImage = smallImage; self.smallText = smallText
        }
        private enum CodingKeys: String, CodingKey { case largeImage = "large_image", largeText = "large_text", smallImage = "small_image", smallText = "small_text" }
    }
    public struct Button: Encodable, Equatable, Sendable { public let label: String; public let url: String }
    public private(set) var details: String?
    public private(set) var state: String?
    public private(set) var timestamps: Timestamps?
    public private(set) var assets: Assets?
    public let buttons: [Button]?

    public init(session: PlaySession?, game: GameDetails? = nil, options: DiscordPresenceOptions = .init(), custom: BloxstrapPresenceState? = nil, artwork: [String: URL] = [:], runningPlayers: Int = 1) {
        let multiplePlayers = runningPlayers > 1
        let session = multiplePlayers ? nil : session
        // Reject stale metadata and malformed place IDs rather than publishing a different game's identity.
        let placeID = session.flatMap { try? GameShortcut(name: "Game", placeID: $0.placeID).placeID }
        let metadata = game.flatMap { $0.isValid && $0.placeID == placeID ? $0 : nil }
        let revealGame = options.showGameActivity && session != nil && placeID != nil
        details = multiplePlayers ? "Multiple Roblox Players" : revealGame ? Self.text(session?.name ?? "", fallback: "Playing Roblox") : (session == nil ? "Browsing Roblox" : "Playing Roblox")
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

        guard revealGame, options.allowGameControl, let custom else { return }
        func resolve<T>(_ value: PresenceOverride<T>, fallback: T?) -> T? {
            switch value { case .standard: fallback; case .cleared: nil; case .value(let value): value }
        }
        details = resolve(custom.details, fallback: details)
        state = resolve(custom.state, fallback: state)
        if options.showPlayTime {
            let start = resolve(custom.timeStart, fallback: timestamps?.start)
            let requestedEnd = resolve(custom.timeEnd, fallback: nil)
            let end = requestedEnd.flatMap { value in
                if let start, value < start { return nil as Int64? }
                return value
            }
            timestamps = start == nil && end == nil ? nil : Timestamps(start: start, end: end)
        }
        if options.showArtwork {
            func image(_ value: BloxstrapPresenceState.Image, fallback: String?) -> String? {
                guard !value.hidden else { return nil }
                guard let id = value.assetID else { return fallback }
                return GameDetails.permittedIcon(artwork[id])?.absoluteString
            }
            let large = image(custom.largeImage, fallback: assets?.largeImage)
            let small = image(custom.smallImage, fallback: nil)
            func hover(_ value: String?, fallback: String? = nil) -> String? {
                guard let value else { return fallback }
                return value.unicodeScalars.count >= 2 ? value : nil
            }
            assets = large == nil && small == nil ? nil : Assets(
                largeImage: large, largeText: large == nil ? nil : hover(custom.largeImage.hoverText, fallback: assets?.largeText),
                smallImage: small, smallText: small == nil ? nil : hover(custom.smallImage.hoverText))
        }
    }

    private static func text(_ value: String, fallback: String) -> String {
        let result = BloxstrapPresenceState.text(value)
        return result.unicodeScalars.count >= 2 ? result : fallback
    }
}
