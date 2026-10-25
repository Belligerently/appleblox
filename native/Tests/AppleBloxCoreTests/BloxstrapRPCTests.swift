import Foundation
import Testing
@testable import AppleBloxCore

private func sdkPatch(_ json: String) throws -> BloxstrapPresencePatch {
    try #require(BloxstrapPresencePatch.parse("[FLog::Output] [BloxstrapRPC] {\"command\":\"SetRichPresence\",\"data\":\(json)}"))
}

@Test func sdkParserRejectsUnrelatedMalformedOversizedAndUnsafeFields() throws {
    for line in ["[BloxstrapRPC] {}", "[FLog::Output] [BloxstrapRPC] []",
                 "[FLog::Output] [BloxstrapRPC] broken [FLog::SingleSurfaceApp] returnToLuaApp", "[FLog::Output] [BloxstrapRPC] {broken}",
                 "[FLog::Output] [BloxstrapRPC] {\"command\":\"SetLaunchData\",\"data\":\"secret\"}",
                 "[FLog::Output] [BloxstrapRPC] {\"command\":\"RunCommand\",\"data\":{}}"] {
        #expect(PlayerLogEvent.parse(line) == nil)
    }
    for json in [#"{"details":false}"#, #"{"timeStart":-1}"#, #"{"timeEnd":253402300800}"#,
                 #"{"largeImage":{"assetId":"https://evil.test/image"}}"#, #"{"smallImage":{"assetId":0}}"#,
                 #"{"smallImage":{"assetId":1.5}}"#, #"{"largeImage":{"assetId":"rbxassetid://-1"}}"#,
                 "{\"details\":\"" + String(repeating: "a", count: 16_384) + "\"}"] {
        let line = "[FLog::Output] [BloxstrapRPC] {\"command\":\"SetRichPresence\",\"data\":\(json)}"
        #expect(PlayerLogEvent.parse(line) == nil)
    }
    #expect(try sdkPatch(#"{"largeImage":{"assetId":"rbxassetid://123"}}"#).largeImage?.assetId == "123")
}

@Test func sdkStatePreservesOmittedAndNullValuesAndSupportsClearAndReset() throws {
    var state = BloxstrapPresenceState()
    try state.apply(sdkPatch(#"{"details":"Round 1","state":"In lobby","largeImage":{"assetId":123,"hoverText":"Map"}}"#))
    try state.apply(sdkPatch(#"{"details":null,"state":"Round started","largeImage":{"hoverText":"New map"}}"#))
    #expect(state.details == .value("Round 1"))
    #expect(state.state == .value("Round started"))
    #expect(state.largeImage.assetID == "123" && state.largeImage.hoverText == "New map")
    try state.apply(sdkPatch(#"{"details":"","state":"<reset>","largeImage":{"clear":true}}"#))
    #expect(state.details == .cleared && state.state == .standard)
    #expect(state.assetIDs.isEmpty)
    try state.apply(sdkPatch(#"{"largeImage":{"assetId":456}}"#))
    #expect(state.assetIDs.isEmpty) // Clear persists until explicitly removed or reset.
    try state.apply(sdkPatch(#"{"largeImage":{"clear":false}}"#))
    #expect(state.assetIDs == ["456"])
    try state.apply(sdkPatch(#"{"largeImage":{"reset":true}}"#))
    #expect(state.largeImage.assetID == nil && !state.largeImage.hidden)
}

@Test func sdkPresenceHonorsEveryVisibilityGateAndNeverAddsInviteData() throws {
    var state = BloxstrapPresenceState()
    try state.apply(sdkPatch(#"{"details":"Secret map","state":"Private round","timeStart":123,"timeEnd":456,"largeImage":{"assetId":10},"smallImage":{"assetId":11}}"#))
    let session = PlaySession(placeID: "1818", name: "Default game")
    let images = ["10": URL(string: "https://tr.rbxcdn.com/large.png")!, "11": URL(string: "https://tr.rbxcdn.com/small.png")!]
    for allow in [false, true] {
        for game in [false, true] {
            for artwork in [false, true] {
                for time in [false, true] {
                    let options = DiscordPresenceOptions(showGameActivity: game, showPlayTime: time, showArtwork: artwork, showGameButton: false, allowGameControl: allow)
                    let activity = DiscordActivity(session: session, options: options, custom: state, artwork: images)
                    #expect(activity.details == (allow && game ? "Secret map" : (game ? "Default game" : "Playing Roblox")))
                    #expect(activity.state == (allow && game ? "Private round" : "Playing with AppleBlox Native"))
                    #expect((activity.assets != nil) == (allow && game && artwork))
                    #expect((activity.timestamps != nil) == time)
                    if allow && game && time { #expect(activity.timestamps?.end == 456) }
                    #expect(activity.buttons == nil)
                }
            }
        }
    }
    let browsing = DiscordActivity(session: nil, options: .init(allowGameControl: true), custom: state)
    #expect(browsing.details == "Browsing Roblox")
    #expect(browsing.timestamps == nil)
}

@Test func sdkTextAndTimeClearResetAndUnicodeAreSafeToEncode() throws {
    var state = BloxstrapPresenceState()
    let longText = String(repeating: "🌹", count: 128) + "\nsecret"
    let data = try JSONSerialization.data(withJSONObject: ["details": longText, "state": "", "timeStart": 0, "timeEnd": 0])
    try state.apply(sdkPatch(String(decoding: data, as: UTF8.self)))
    let session = PlaySession(placeID: "1818", name: "Fallback")
    var activity = DiscordActivity(session: session, options: .init(allowGameControl: true), custom: state)
    #expect(activity.details?.utf8.count == 128 && activity.details?.contains("\n") == false)
    #expect(activity.state == nil && activity.timestamps == nil)
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as? [String: Any])
    #expect(encoded["state"] == nil && encoded["timestamps"] == nil)
    try state.apply(sdkPatch(#"{"details":"<reset>","state":"<reset>","timeStart":200,"timeEnd":100}"#))
    activity = DiscordActivity(session: session, options: .init(allowGameControl: true), custom: state)
    #expect(activity.details == "Fallback" && activity.state == "Playing with AppleBlox Native")
    #expect(activity.timestamps?.start == 200 && activity.timestamps?.end == nil)
}

@Test func sdkArtworkClearResetAndLateImagesRespectCurrentIDs() throws {
    let game = GameDetails(placeID: "1818", universeID: 1, name: "Game", creator: "Creator", playing: nil,
                           iconURL: URL(string: "https://tr.rbxcdn.com/default.png"), fetchedAt: Date())
    let session = PlaySession(placeID: "1818", name: "Game")
    let options = DiscordPresenceOptions(showArtwork: true, allowGameControl: true)
    var state = BloxstrapPresenceState()
    try state.apply(sdkPatch(#"{"largeImage":{"assetId":10,"hoverText":"Custom"},"smallImage":{"assetId":11,"hoverText":"Small"}}"#))
    var activity = DiscordActivity(session: session, game: game, options: options, custom: state, artwork: ["10": URL(string: "https://evil.test/image")!])
    #expect(activity.assets == nil)
    let images = ["10": URL(string: "https://tr.rbxcdn.com/custom.png")!, "11": URL(string: "https://tr.rbxcdn.com/small.png")!]
    activity = DiscordActivity(session: session, game: game, options: options, custom: state, artwork: images)
    #expect(activity.assets?.largeText == "Custom" && activity.assets?.smallText == "Small")
    try state.apply(sdkPatch(#"{"largeImage":{"hoverText":""},"smallImage":{"hoverText":"x"}}"#))
    activity = DiscordActivity(session: session, game: game, options: options, custom: state, artwork: images)
    #expect(activity.assets?.largeText == nil && activity.assets?.smallText == nil)
    try state.apply(sdkPatch(#"{"largeImage":{"clear":true},"smallImage":{"clear":true}}"#))
    #expect(DiscordActivity(session: session, game: game, options: options, custom: state, artwork: images).assets == nil)
    try state.apply(sdkPatch(#"{"largeImage":{"reset":true}}"#))
    #expect(DiscordActivity(session: session, game: game, options: options, custom: state, artwork: images).assets?.largeImage == game.iconURL?.absoluteString)
    try state.apply(sdkPatch(#"{"largeImage":{"assetId":12}}"#))
    #expect(DiscordActivity(session: session, game: game, options: options, custom: state, artwork: images).assets == nil)
}

private actor SDKFetchCounter {
    var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}

@Test func sdkArtworkUsesFixedPublicEndpointCachesAndLimitsRetries() async throws {
    let counter = SDKFetchCounter()
    let catalog = PresenceArtworkCatalog { url in
        await counter.add(url)
        return Data(#"{"data":[{"targetId":10,"state":"Completed","imageUrl":"https://tr.rbxcdn.com/ten.png"},{"targetId":11,"state":"Completed","imageUrl":"https://evil.test/eleven.png"},{"targetId":99,"state":"Completed","imageUrl":"https://tr.rbxcdn.com/unrequested.png"}]}"#.utf8)
    }
    let now = Date()
    let result = await catalog.images(for: ["10", "11", "https://evil.test/", "-1"], now: now)
    #expect(result.count == 1 && result["10"]?.host == "tr.rbxcdn.com")
    #expect(await catalog.images(for: ["10"], now: now) == result)
    #expect(await catalog.images(for: ["11"], now: now).isEmpty)
    #expect(await counter.urls.count == 1)
    _ = await catalog.images(for: ["11"], now: now.addingTimeInterval(11))
    let urls = await counter.urls
    #expect(urls.count == 2)
    #expect(urls.allSatisfy { $0.scheme == "https" && $0.host == "thumbnails.roblox.com" && $0.path == "/v1/assets" })
    #expect(URLComponents(url: urls[0], resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "assetIds" }?.value == "10,11")
}

@Test func sdkArtworkOfflineAndPendingResponsesFallBackWithoutThrowing() async {
    let offline = PresenceArtworkCatalog { _ in throw URLError(.notConnectedToInternet) }
    #expect(await offline.images(for: ["10"]).isEmpty)
    let pending = PresenceArtworkCatalog { _ in Data(#"{"data":[{"targetId":10,"state":"Pending","imageUrl":"https://tr.rbxcdn.com/pending.png"}]}"#.utf8) }
    #expect(await pending.images(for: ["10"]).isEmpty)
}

@Test func sdkSettingsMigrateOffAndPersistIndependently() throws {
    var settings = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
    #expect(!settings.bloxstrapSDK && !settings.gameControlledPresence && !settings.needsLogTracking)
    settings.bloxstrapSDK = true
    #expect(settings.needsLogTracking && !settings.allowsGamePresence)
    settings.gameControlledPresence = true
    settings.discordPresence = true
    #expect(settings.allowsGamePresence)
    settings.discordGameActivity = false
    #expect(!settings.allowsGamePresence)
    #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)).validated() == settings)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"bloxstrapSDK":"true"}"#.utf8)) }
}

@Test func sdkLogMessagesRemainOrderedAcrossPartialWritesAndSessions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABSDKLogs-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("Player_sdk.log")
    let sdk = "[FLog::Output] [BloxstrapRPC] {\"command\":\"SetRichPresence\",\"data\":{\"details\":\"Old session\"}}"
    try Data((sdk + "\n").utf8).write(to: file)
    let reader = PlayerLogReader()
    #expect(try await reader.poll(directory: root).isEmpty)
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("[FLog::Output] ! Joining game 'test' place 1818 at 127.0.0.1\n".utf8))
    try handle.write(contentsOf: Data(sdk.utf8))
    #expect(try await reader.poll(directory: root) == [.joining("1818")])
    try handle.write(contentsOf: Data("\n[FLog::SingleSurfaceApp] returnToLuaApp\n".utf8))
    #expect(try await reader.poll(directory: root) == [.richPresence(sdkPatch(#"{"details":"Old session"}"#)), .left])
}

@Test func sdkCancelledArtworkLookupDoesNotPopulateCache() async throws {
    let started = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    let counter = SDKFetchCounter()
    let catalog = PresenceArtworkCatalog { url in
        await counter.add(url)
        started.continuation.yield(())
        for await _ in release.stream { break }
        return Data(#"{"data":[{"targetId":10,"state":"Completed","imageUrl":"https://tr.rbxcdn.com/ten.png"}]}"#.utf8)
    }
    let now = Date()
    let task = Task { await catalog.images(for: ["10"], now: now) }
    for await _ in started.stream { break }
    task.cancel()
    release.continuation.finish()
    #expect(await task.value.isEmpty)
    #expect(await catalog.images(for: ["10"], now: now).isEmpty)
    #expect(await counter.urls.count == 1)
    #expect(await catalog.images(for: ["10"], now: now.addingTimeInterval(11)).count == 1)
    #expect(await counter.urls.count == 2)
}
