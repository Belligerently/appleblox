import Foundation
import Testing
@testable import AppleBloxCore

private func activityGame(placeID: String = "1818", creator: String = "ROBLOX", icon: String? = "https://tr.rbxcdn.com/public-game.png") -> GameDetails {
    GameDetails(placeID: placeID, universeID: 111, name: "Crossroads", creator: creator, playing: nil,
                iconURL: icon.flatMap(URL.init(string:)), fetchedAt: Date())
}

@Test func discordActivityDefaultsPreserveExistingPublicFields() throws {
    let session = PlaySession(placeID: "1818", name: "Crossroads", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let activity = DiscordActivity(session: session, game: activityGame())
    #expect(activity.details == "Crossroads")
    #expect(activity.state == "Playing with AppleBlox Native")
    #expect(activity.timestamps?.start == 1_700_000_000)
    #expect(activity.assets == nil)
    #expect(activity.buttons?.first?.url == "https://www.roblox.com/games/1818/")
}

@Test func hiddenGameNeverLeaksIdentityThroughAssetsCreatorOrButton() throws {
    let session = PlaySession(placeID: "1818", name: "Secret experience", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let game = activityGame(creator: "Identifiable creator")
    for time in [false, true] {
        for artwork in [false, true] {
            for button in [false, true] {
                let options = DiscordPresenceOptions(showGameActivity: false, showPlayTime: time, showArtwork: artwork, showGameButton: button)
                let activity = DiscordActivity(session: session, game: game, options: options)
                #expect(activity.details == "Playing Roblox")
                #expect(activity.state == "Playing with AppleBlox Native")
                #expect((activity.timestamps != nil) == time)
                #expect(activity.assets == nil)
                #expect(activity.buttons == nil)
                let json = String(decoding: try JSONEncoder().encode(activity), as: UTF8.self)
                for privatePart in ["1818", "Secret experience", "Identifiable creator", "rbxcdn", "Crossroads"] {
                    #expect(!json.contains(privatePart))
                }
            }
        }
    }
}

@Test func discordArtworkAndCreatorUseOnlyMatchingPublicMetadata() {
    let session = PlaySession(placeID: "1818", name: "Crossroads")
    let options = DiscordPresenceOptions(showArtwork: true, showGameButton: false)
    let activity = DiscordActivity(session: session, game: activityGame(), options: options)
    #expect(activity.assets?.largeImage == "https://tr.rbxcdn.com/public-game.png")
    #expect(activity.assets?.largeText == "Crossroads")
    #expect(activity.state == "by ROBLOX")
    #expect(activity.buttons == nil)
    for game in [activityGame(placeID: "999"), activityGame(icon: "https://rbxcdn.com.evil.test/image.png"),
                 activityGame(icon: "http://tr.rbxcdn.com/image.png"), activityGame(icon: "https://user:password@tr.rbxcdn.com/image.png")] {
        let rejected = DiscordActivity(session: session, game: game, options: options)
        #expect(rejected.assets == nil)
        #expect(rejected.state == "Playing with AppleBlox Native")
    }
}

@Test func missingArtworkAndOfflineMetadataKeepPresenceUsable() {
    let session = PlaySession(placeID: "1818", name: "Saved game")
    let options = DiscordPresenceOptions(showArtwork: true)
    let missingImage = DiscordActivity(session: session, game: activityGame(icon: nil), options: options)
    #expect(missingImage.assets == nil)
    #expect(missingImage.state == "by ROBLOX")
    let offline = DiscordActivity(session: session, options: options)
    #expect(offline.details == "Saved game")
    #expect(offline.assets == nil)
    #expect(offline.buttons != nil)
    let home = DiscordActivity(session: nil, game: activityGame(), options: options)
    #expect(home.details == "Browsing Roblox")
    #expect(home.timestamps == nil && home.assets == nil && home.buttons == nil)
}

@Test func discordActivityBoundsTextAndRejectsMalformedSessionData() {
    let name = "\n" + String(repeating: "🧑‍🚀", count: 100)
    let session = PlaySession(placeID: "1818", name: name)
    let game = activityGame(creator: String(repeating: "x", count: 250))
    let activity = DiscordActivity(session: session, game: game, options: .init(showArtwork: true))
    #expect((activity.details ?? "").unicodeScalars.count <= 128)
    #expect((activity.state ?? "").unicodeScalars.count <= 128)
    #expect(activity.details?.contains("\n") == false)
    for place in ["1818?token=secret", "https://evil.test", "0", "-1"] {
        let invalid = DiscordActivity(session: PlaySession(placeID: place, name: "Bad game"), game: game, options: .init(showArtwork: true))
        #expect(invalid.details == "Playing Roblox")
        #expect(invalid.assets == nil && invalid.buttons == nil)
    }
    for time in [-1.0, Double.infinity, Double.nan] {
        let invalid = DiscordActivity(session: PlaySession(placeID: "1818", name: "Test", startedAt: Date(timeIntervalSince1970: time)))
        #expect(invalid.timestamps == nil)
    }
}

@Test func richerDiscordSettingsMigrateWithoutEnablingArtwork() throws {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(FeatureSettings())) as? [String: Any])
    for key in ["discordGameActivity", "discordArtwork", "discordGameButton"] { object.removeValue(forKey: key) }
    object["discordPresence"] = true
    object["discordPlayTime"] = false
    var migrated = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: object)).validated()
    #expect(migrated.discordGameActivity && migrated.discordGameButton)
    #expect(!migrated.discordArtwork && !migrated.discordPlayTime)
    migrated.discordGameActivity = false
    migrated.discordArtwork = true
    migrated.discordGameButton = false
    #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)).validated() == migrated)
    object["discordArtwork"] = "true"
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: object)) }
}
