import Foundation

public struct ContentMod: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public let fileCount: Int
    public var iconColorHex: String?
    public init(id: UUID = UUID(), name: String, enabled: Bool = true, fileCount: Int) {
        self.id = id; self.name = name; self.enabled = enabled; self.fileCount = fileCount
    }
}

public struct RobloxAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let displayName: String
}

public struct FeatureSettings: Codable, Equatable, Sendable {
    public var mods: [ContentMod] = []
    public var applyModsOnLaunch = false
    public var accounts: [RobloxAccount] = []
    public var selectedAccountID: Int64?
    public var discordPresence = false
    public var discordClientID = "1257650541677383721"
    public var trackHistory = false
    public var checkUpdatesOnOpen = false
    public var automaticUpdates = false
    public var newPlayerInstance = false
    public var quitAfterGame = false
    public var quitLauncherWithPlayer = false
    public var returnToWebsite = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case mods, applyModsOnLaunch, accounts, selectedAccountID, discordPresence, discordClientID, trackHistory, checkUpdatesOnOpen, automaticUpdates, newPlayerInstance, quitAfterGame, quitLauncherWithPlayer, returnToWebsite
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mods = try values.decodeIfPresent([ContentMod].self, forKey: .mods) ?? mods
        applyModsOnLaunch = try values.decodeIfPresent(Bool.self, forKey: .applyModsOnLaunch) ?? applyModsOnLaunch
        accounts = try values.decodeIfPresent([RobloxAccount].self, forKey: .accounts) ?? accounts
        selectedAccountID = try values.decodeIfPresent(Int64.self, forKey: .selectedAccountID)
        discordPresence = try values.decodeIfPresent(Bool.self, forKey: .discordPresence) ?? discordPresence
        discordClientID = try values.decodeIfPresent(String.self, forKey: .discordClientID) ?? discordClientID
        trackHistory = try values.decodeIfPresent(Bool.self, forKey: .trackHistory) ?? trackHistory
        checkUpdatesOnOpen = try values.decodeIfPresent(Bool.self, forKey: .checkUpdatesOnOpen) ?? checkUpdatesOnOpen
        automaticUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? automaticUpdates
        newPlayerInstance = try values.decodeIfPresent(Bool.self, forKey: .newPlayerInstance) ?? newPlayerInstance
        quitAfterGame = try values.decodeIfPresent(Bool.self, forKey: .quitAfterGame) ?? quitAfterGame
        quitLauncherWithPlayer = try values.decodeIfPresent(Bool.self, forKey: .quitLauncherWithPlayer) ?? quitLauncherWithPlayer
        returnToWebsite = try values.decodeIfPresent(Bool.self, forKey: .returnToWebsite) ?? returnToWebsite
    }

    public func validated() throws -> FeatureSettings {
        guard Set(mods.map(\.id)).count == mods.count, mods.allSatisfy({ !$0.name.isEmpty && $0.fileCount > 0 }),
              Set(accounts.map(\.id)).count == accounts.count, accounts.allSatisfy({ $0.id > 0 }),
              selectedAccountID == nil || accounts.contains(where: { $0.id == selectedAccountID }),
              !discordClientID.isEmpty, discordClientID.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw FeatureError.message("The feature settings contain invalid or duplicate records.")
        }
        for mod in mods {
            if let hex = mod.iconColorHex { _ = try IconColor(hex: hex) }
        }
        return self
    }
}

public enum FeatureError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let text): text } }
}

public struct LaunchLink: Equatable, Sendable {
    public let url: URL
    public let placeID: String?
    public init(_ url: URL) throws {
        guard url.absoluteString.utf8.count <= 32_768,
              let scheme = url.scheme?.lowercased(), ["roblox", "roblox-player", "appleblox-native"].contains(scheme) else {
            throw FeatureError.message("Use a Roblox launch link or an appleblox-native://play?placeId=… link.")
        }
        if scheme == "appleblox-native" {
            guard url.host == "play", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let id = parts.queryItems?.first(where: { $0.name == "placeId" })?.value else {
                throw FeatureError.message("This AppleBlox link is missing its place ID.")
            }
            let game = try GameShortcut(name: "Linked game", placeID: id)
            self.url = game.launchURL; placeID = game.placeID
        } else {
            self.url = url
            let rawID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name.lowercased() == "placeid" }?.value
            if let rawID { placeID = try GameShortcut(name: "Linked game", placeID: rawID).placeID }
            else { placeID = nil }
        }
    }
}

public struct LegacyEngineProfile: Decodable, Sendable {
    private struct Row: Decodable, Sendable { let flag: String; let enabled: Bool; let value: FlagValue? }
    public let name: String
    public let games: [String]?
    private let flags: [Row]

    public func nativeProfile() throws -> EngineProfile {
        var profile = EngineProfile(name: name)
        for row in flags where row.enabled {
            guard let value = row.value else { throw EngineError.invalidValue(row.flag) }
            guard profile.customFlags[row.flag] == nil else { throw FeatureError.message("Duplicate flag in legacy profile: \(row.flag)") }
            profile.customFlags[row.flag] = value
        }
        return try profile.validated()
    }
}
