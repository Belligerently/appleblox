import Foundation
import Testing
@testable import AppleBloxCore

@Test func appearanceMigratesOldSettingsAndRoundTrips() throws {
    let old = Data(#"{"version":1,"shortcuts":[]}"#.utf8)
    var configuration = try JSONDecoder().decode(NativeConfiguration.self, from: old)
    #expect(configuration.appearance == AppearanceSettings())
    configuration.appearance.theme = .dark
    configuration.appearance.reduceMotion = true
    configuration.appearance.reduceTransparency = true
    configuration.appearance.showGameArtwork = false
    let data = try JSONEncoder().encode(configuration)
    #expect(try JSONDecoder().decode(NativeConfiguration.self, from: data).validated() == configuration)
    let partial = try JSONDecoder().decode(AppearanceSettings.self, from: Data(#"{"theme":"Light"}"#.utf8))
    #expect(partial.theme == .light)
    #expect(partial.showGameArtwork)
}

@Test func invalidAppearanceDoesNotOverwriteSettings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ConfigurationStore(directory: directory)
    let data = Data(#"{"version":1,"shortcuts":[],"appearance":{"theme":"unknown"}}"#.utf8)
    try data.write(to: store.fileURL)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: store.fileURL) == data)
}

@Test func gameInputAcceptsOnlyCanonicalRobloxPlaces() throws {
    for text in [" 0001818 ", "https://www.roblox.com/games/1818/Crossroads", "roblox.com/games/1818/Title",
                 "https://www.roblox.com/en-us/games/1818/Title?privateServerLinkCode=ignored", "https://m.roblox.com/games/1818"] {
        #expect(try RobloxPlaceInput.placeID(from: text) == "1818")
    }
    for text in ["https://roblox.com.evil.test/games/1818", "https://evil.test/roblox.com/games/1818",
                 "https://roblox.com@evil.test/games/1818", "https://user:password@roblox.com/games/1818",
                 "http://roblox.com/games/1818", "https://roblox.com:443/games/1818", "https://roblox.com/games/0",
                 "https://roblox.com/share?code=123", "https://roblox.com/catalog/1818", "../1818", "１２３", "-1"] {
        #expect(throws: (any Error).self) { try RobloxPlaceInput.placeID(from: text) }
    }
}

private actor CatalogStub {
    var requests: [URL] = []
    let iconState: String
    let iconHost: String
    init(iconState: String = "Completed", iconHost: String = "tr.rbxcdn.com") {
        self.iconState = iconState; self.iconHost = iconHost
    }
    func fetch(_ url: URL) throws -> Data {
        requests.append(url)
        let json: String
        switch url.host {
        case "apis.roblox.com": json = #"{"universeId":111}"#
        case "games.roblox.com": json = #"{"data":[{"id":111,"name":"Crossroads","creator":{"name":"ROBLOX"},"playing":12}]}"#
        case "thumbnails.roblox.com": json = "{\"data\":[{\"targetId\":111,\"state\":\"\(iconState)\",\"imageUrl\":\"https://\(iconHost)/image.png\"}]}"
        default: throw FeatureError.message("Unexpected request")
        }
        return Data(json.utf8)
    }
}

@Test func catalogResolvesPlaceDetailsAndUsesFreshCache() async throws {
    let stub = CatalogStub()
    let catalog = GameCatalog(fetch: { try await stub.fetch($0) })
    let first = try await catalog.game(for: "1818")
    #expect(first.name == "Crossroads")
    #expect(first.creator == "ROBLOX")
    #expect(first.playing == 12)
    #expect(first.iconURL?.host == "tr.rbxcdn.com")
    #expect(try await catalog.game(for: "https://www.roblox.com/games/1818") == first)
    #expect(await stub.requests.count == 3)
    _ = try await catalog.game(for: "1818", refresh: true)
    #expect(await stub.requests.count == 6)
}

@Test func catalogKeepsTextWhenArtworkIsPendingOrUntrusted() async throws {
    for stub in [CatalogStub(iconState: "Pending"), CatalogStub(iconHost: "rbxcdn.com.evil.test")] {
        let catalog = GameCatalog(fetch: { try await stub.fetch($0) })
        let details = try await catalog.game(for: "1818")
        #expect(details.name == "Crossroads")
        #expect(details.iconURL == nil)
    }
}

@Test func catalogRecoversPersistedDetailsWhenOffline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stale = GameDetails(placeID: "1818", universeID: 111, name: "Saved game", creator: "Creator", playing: 10,
                            iconURL: nil, fetchedAt: Date(timeIntervalSince1970: 1))
    try JSONEncoder().encode([stale, stale]).write(to: directory.appendingPathComponent("game-details-cache.json"))
    let catalog = GameCatalog(directory: directory, fetch: { _ in throw URLError(.notConnectedToInternet) })
    #expect(try await catalog.game(for: "1818") == stale)
    #expect(stale.isStale)
    #expect(throws: (any Error).self) { try RobloxPlaceInput.placeID(from: "https://untrusted.test/1818") }
}

@Test func catalogHandlesPrivateGamesAndUnavailableArtwork() async throws {
    let privateCatalog = GameCatalog(fetch: { url in
        Data((url.host == "apis.roblox.com" ? #"{"universeId":111}"# : #"{"data":[]}"#).utf8)
    })
    await #expect(throws: (any Error).self) { try await privateCatalog.game(for: "1818") }
    let stub = CatalogStub()
    let catalog = GameCatalog(fetch: { url in
        if url.host == "thumbnails.roblox.com" { throw URLError(.timedOut) }
        return try await stub.fetch(url)
    })
    let game = try await catalog.game(for: "1818")
    #expect(game.name == "Crossroads")
    #expect(game.iconURL == nil)
}

@Test func canceledCatalogLookupDoesNotFallbackToSavedDetails() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stale = GameDetails(placeID: "1818", universeID: 111, name: "Saved", creator: "Creator", playing: nil,
                            iconURL: nil, fetchedAt: Date(timeIntervalSince1970: 1))
    try JSONEncoder().encode([stale]).write(to: directory.appendingPathComponent("game-details-cache.json"))
    let catalog = GameCatalog(directory: directory, fetch: { _ in
        try await Task.sleep(for: .seconds(60))
        return Data()
    })
    let lookup = Task { try await catalog.game(for: "1818") }
    lookup.cancel()
    do {
        _ = try await lookup.value
        Issue.record("A cancelled lookup should throw")
    } catch is CancellationError {} catch { Issue.record("Expected cancellation, got \(error)") }
}
