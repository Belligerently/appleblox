import Foundation
import Testing
@testable import AppleBloxCore

private let serverData = Data(#"{"ip":"8.8.8.8","city":"Mountain View","region":"California","country":"US","loc":"0,0","org":"not retained"}"#.utf8)
private actor LocationRequests {
    var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}

@Test func serverEndpointAcceptsOnlyPublicIPv4AndValidPorts() throws {
    #expect(try ServerEndpoint(address: "8.8.8.8", port: 5000).address == "8.8.8.8")
    for address in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.0.1", "169.254.1.1", "0.0.0.0", "100.64.0.1",
                    "198.18.0.1", "192.0.2.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255",
                    "192.88.99.1", "2001:db8::1", "8.8.8.8/secret", "08.8.8.8", "8.8.8.256", "8.8.8", "https://evil.test", "8..8.8", "８.8.8.8"] {
        #expect(!ServerEndpoint.publicIPv4(address))
        #expect(throws: FeatureError.self) { try ServerEndpoint(address: address, port: 5000) }
    }
    for port in [-1, 0, 65536, Int.max] { #expect(throws: FeatureError.self) { try ServerEndpoint(address: "8.8.8.8", port: port) } }
}

@Test func confirmedServerParserRejectsOutputSpoofingAndMalformedLines() throws {
    let endpoint = try ServerEndpoint(address: "8.8.8.8", port: 5000)
    #expect(PlayerLogEvent.parse("timestamp [FLog::Network] serverId: 8.8.8.8|5000") == .serverConnected(endpoint))
    for line in ["[FLog::Output] [FLog::Network] serverId: 8.8.8.8|5000", "[FLog::Network] serverId: 8.8.8.8|0",
                 "serverId: 8.8.8.8|5000", "[FLog::Network] serverId: 127.0.0.1|5000", "[FLog::Network] serverId: 8.8.8.8|5000 trailing",
                 "[FLog::Network] serverId: 8.8.8.8|5000" + String(repeating: " ", count: 4096)] {
        #expect(PlayerLogEvent.parse(line) == nil)
    }
}

@Test func serverLocationUsesExplicitEndpointCachesAndThrottlesOtherRequests() async throws {
    let requests = LocationRequests()
    let service = ServerLocationService { url in await requests.add(url); return serverData }
    let endpoint = try ServerEndpoint(address: "8.8.8.8", port: 5000)
    let now = Date()
    let location = try await service.region(for: endpoint, now: now)
    #expect(location.description == "Mountain View, California, US")
    #expect(try await service.region(for: endpoint, now: now) == location)
    let other = try ServerEndpoint(address: "1.1.1.1", port: 5000)
    await #expect(throws: FeatureError.self) { try await service.region(for: other, now: now) }
    let urls = await requests.urls
    #expect(urls.map(\.absoluteString) == ["https://ipinfo.io/8.8.8.8/json"])
}

@Test func serverLocationRejectsMismatchedBogonMissingAndOversizedResponses() throws {
    for data in [Data(#"{"ip":"1.1.1.1","country":"US"}"#.utf8), Data(#"{"ip":"8.8.8.8","country":"US","bogon":true}"#.utf8),
                 Data(#"{"ip":"8.8.8.8"}"#.utf8), Data(#"{"ip":"8.8.8.8","country":"USA"}"#.utf8),
                 Data(#"{"ip":"8.8.8.8","country":"us"}"#.utf8), Data("{".utf8), Data(repeating: 32, count: 16_385)] {
        #expect(throws: (any Error).self) { try ServerRegion.decode(data, address: "8.8.8.8") }
    }
    let minimal = try ServerRegion.decode(Data(#"{"ip":"8.8.8.8","country":"US","city":"","region":"US"}"#.utf8), address: "8.8.8.8")
    #expect(minimal.description == "US")
}

@Test func cancelledServerLookupCannotPopulateCacheAndFailuresRespectCooldown() async throws {
    let started = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    let requests = LocationRequests()
    let service = ServerLocationService { url in
        await requests.add(url)
        started.continuation.yield(())
        for await _ in release.stream { break }
        return serverData
    }
    let endpoint = try ServerEndpoint(address: "8.8.8.8", port: 5000)
    let now = Date()
    let task = Task { try await service.region(for: endpoint, now: now) }
    for await _ in started.stream { break }
    task.cancel(); release.continuation.finish()
    await #expect(throws: CancellationError.self) { try await task.value }
    await #expect(throws: FeatureError.self) { try await service.region(for: endpoint, now: now) }
    #expect(try await service.region(for: endpoint, now: now.addingTimeInterval(11)).country == "US")
    #expect(await requests.urls.count == 2)
    let offline = ServerLocationService { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: URLError.self) { try await offline.region(for: endpoint, now: now) }
    await #expect(throws: FeatureError.self) { try await offline.region(for: endpoint, now: now) }
}

@Test func serverConnectionsDeduplicateWithinSessionAndResetOnLeave() throws {
    var tracker = ServerConnectionTracker()
    let session = UUID()
    let endpoint = try ServerEndpoint(address: "8.8.8.8", port: 5000)
    let mutationResult1 = tracker.connect(sessionID: session, endpoint: endpoint)
    #expect(mutationResult1)
    let mutationResult2 = tracker.connect(sessionID: session, endpoint: endpoint)
    #expect(!mutationResult2)
    let mutationResult3 = try tracker.connect(sessionID: session, endpoint: ServerEndpoint(address: "8.8.8.8", port: 5001))
    #expect(mutationResult3)
    let mutationResult4 = tracker.connect(sessionID: UUID(), endpoint: endpoint)
    #expect(mutationResult4)
    tracker.reset()
    #expect(tracker.sessionID == nil && tracker.endpoint == nil)
    let mutationResult5 = tracker.connect(sessionID: session, endpoint: endpoint)
    #expect(mutationResult5)
}

@Test func serverNoticesAreGenericWithoutLookupAndSoundIsIndependent() throws {
    let location = try ServerRegion.decode(serverData, address: "8.8.8.8")
    for sound in [false, true] {
        let generic = ServerJoinedNotice(region: nil, sound: sound)
        #expect(generic.title == "Server Joined" && generic.sound == sound)
        #expect(generic.body == "Connected to a Roblox game server.")
        let regional = ServerJoinedNotice(region: location, sound: sound)
        #expect(regional.body.contains("Mountain View"))
        for privatePart in ["8.8.8.8", "0,0", "not retained"] { #expect(!regional.body.contains(privatePart)) }
    }
    var limiter = ServerNoticeLimiter()
    let now = Date()
    let mutationResult6 = limiter.reserve(now: now)
    #expect(mutationResult6)
    let mutationResult7 = limiter.reserve(now: now.addingTimeInterval(9))
    #expect(!mutationResult7)
    let mutationResult8 = limiter.reserve(now: now.addingTimeInterval(10))
    #expect(mutationResult8)
}

@Test func serverActivitySettingsMigrateOffAndPersistIndependently() throws {
    var features = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
    #expect(!features.serverLocation && !features.serverJoinedNotifications && !features.notificationSounds)
    features.serverLocation = true
    #expect(features.needsLogTracking && !features.serverJoinedNotifications)
    features.serverLocation = false
    features.serverJoinedNotifications = true
    features.notificationSounds = true
    #expect(features.needsLogTracking)
    #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(features)) == features)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"serverLocation":"true"}"#.utf8)) }
}

@Test func serverLogReaderIgnoresOldConnectionsAndWaitsForCompleteNewLines() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABServerLog-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let log = root.appendingPathComponent("Player_server.log")
    let serverLine = "[FLog::Network] serverId: 8.8.8.8|5000"
    try Data((serverLine + "\n").utf8).write(to: log)
    let reader = PlayerLogReader()
    #expect(try await reader.poll(directory: root).isEmpty)
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("[FLog::Output] ! Joining game 'test' place 1818 at 8.8.8.8\n".utf8))
    try handle.write(contentsOf: Data(serverLine.utf8))
    #expect(try await reader.poll(directory: root) == [.joining("1818")])
    try handle.write(contentsOf: Data("\n".utf8))
    #expect(try await reader.poll(directory: root) == [.serverConnected(ServerEndpoint(address: "8.8.8.8", port: 5000))])
}
