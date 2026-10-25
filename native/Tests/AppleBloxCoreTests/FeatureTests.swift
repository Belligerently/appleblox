import Darwin
import Foundation
import Testing
@testable import AppleBloxCore

@Test func gameProfilesAndFeatureSettingsRoundTrip() throws {
    var config = NativeConfiguration()
    var game = try GameShortcut(name: "Test", placeID: "1818")
    game.engineProfileID = config.engine.selectedProfileID
    config.shortcuts = [game]
    config.features.trackHistory = true
    let decoded = try JSONDecoder().decode(NativeConfiguration.self, from: JSONEncoder().encode(config)).validated()
    #expect(decoded == config)
    config.shortcuts[0].engineProfileID = UUID()
    #expect(throws: EngineError.self) { try config.validated() }
    let legacy = try JSONDecoder().decode(NativeConfiguration.self, from: Data(#"{"version":1,"shortcuts":[]}"#.utf8)).validated()
    #expect(legacy.features == FeatureSettings())
}

@Test func legacyProfileImportsOnlyEnabledValidatedFlags() throws {
    let data = Data(#"{"name":"Legacy","type":"game","games":["1818"],"flags":[{"flag":"FFlagDebugSkyGray","enabled":true,"value":"True"},{"flag":"Unknown","enabled":false,"value":null}]}"#.utf8)
    let profile = try JSONDecoder().decode(LegacyEngineProfile.self, from: data)
    #expect(profile.games == ["1818"])
    #expect(try profile.nativeProfile().resolvedFlags() == ["FFlagDebugSkyGray": .boolean(true)])
}

@Test func launchLinksValidateSchemesAndNormalizeAppLinks() throws {
    #expect(try LaunchLink(URL(string: "appleblox-native://play?placeId=0001818")!).url.absoluteString == "roblox://experiences/start?placeId=1818")
    #expect(try LaunchLink(URL(string: "roblox://experiences/start?placeId=1818")!).placeID == "1818")
    for link in ["https://example.com", "file:///tmp/x", "appleblox-native://wrong?placeId=1818", "appleblox-native://play?placeId=0"] {
        #expect(throws: (any Error).self) { try LaunchLink(URL(string: link)!) }
    }
}

@Test func updaterRejectsInvalidReleasesAndArchiveTraversal() throws {
    let valid = try JSONDecoder().decode(RobloxRelease.self, from: Data(#"{"version":"0.744.0.7441080","clientVersionUpload":"version-546c6da637854de3"}"#.utf8)).validated()
    #expect(valid.downloadURL.host == "setup-aws.rbxcdn.com")
    #expect(valid.downloadURL.path.hasSuffix("version-546c6da637854de3-RobloxPlayer.zip"))
    try RobloxUpdateService.validateArchivePaths(["Roblox.app/Contents/Info.plist", "__MACOSX/Roblox.app/._Contents"])
    for paths in [["/tmp/Roblox.app"], ["Roblox.app/../../outside"], ["Roblox.app\\..\\outside"], ["Other.app/file"], []] {
        #expect(throws: FeatureError.self) { try RobloxUpdateService.validateArchivePaths(paths) }
    }
    let invalid = try JSONDecoder().decode(RobloxRelease.self, from: Data(#"{"version":"1.0","clientVersionUpload":"../../oops"}"#.utf8))
    #expect(throws: FeatureError.self) { try invalid.validated() }
}

@Test func playerCookieCodecRoundTripsWithoutCredentialsInErrors() throws {
    let cookie = "test-only-session-not-a-real-credential"
    let file = try PlayerCookies.encode(session: cookie, now: Date(timeIntervalSinceReferenceDate: 10_000))
    #expect(try PlayerCookies.session(from: file) == cookie)
    #expect(file[36] == 5) // Flags at record offset 8, after file/page headers.
    for count in 0..<40 { #expect(throws: FeatureError.self) { try PlayerCookies.session(from: Data(file.prefix(count))) } }
    #expect(throws: FeatureError.self) { try PlayerCookies.encode(session: "bad\nheader") }
}

@Test func logReaderTailsOnlyNewCompleteLines() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABLogs-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let log = root.appendingPathComponent("Player_test.log")
    let join = "[FLog::Output] ! Joining game 'test' place 1818 at 127.0.0.1"
    try Data((join + "\n").utf8).write(to: log)
    let reader = PlayerLogReader()
    #expect(try await reader.poll(directory: root).isEmpty)
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(join.utf8))
    #expect(try await reader.poll(directory: root).isEmpty)
    try handle.write(contentsOf: Data("\n".utf8))
    #expect(try await reader.poll(directory: root) == [.joining("1818")])
    #expect(PlayerLogEvent.parse("[FLog::SingleSurfaceApp] returnToLuaApp") == .left)
    #expect(PlayerLogEvent.parse("unrelated log line containing secrets") == nil)
}

@Test func contentModsApplyRepeatDisableAndRestoreExactly() async throws {
    let fixture = try ModFixture()
    defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.root.appendingPathComponent("mods"))
    let mod = try await store.importFolder(fixture.source)
    try await store.apply([mod], to: fixture.installation)
    #expect(try String(contentsOf: fixture.texture, encoding: .utf8) == "replacement")
    try await store.apply([mod], to: fixture.installation)
    var disabled = mod; disabled.enabled = false
    try await store.apply([disabled], to: fixture.installation)
    #expect(try String(contentsOf: fixture.texture, encoding: .utf8) == "original")
    try await store.apply([mod], to: fixture.installation)
    try await store.restore(fixture.installation)
    #expect(try String(contentsOf: fixture.texture, encoding: .utf8) == "original")
    #expect(await !store.hasBackup(fixture.installation))
}

@Test func modConflictsOutsideEditsAndSymlinksAreRejected() async throws {
    let fixture = try ModFixture()
    defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.root.appendingPathComponent("mods"))
    let first = try await store.importFolder(fixture.source)
    let second = try await store.importFolder(fixture.source)
    await #expect(throws: FeatureError.self) { try await store.apply([first, second], to: fixture.installation) }
    #expect(try String(contentsOf: fixture.texture, encoding: .utf8) == "original")
    try await store.apply([first], to: fixture.installation)
    try Data("outside edit".utf8).write(to: fixture.texture)
    await #expect(throws: FeatureError.self) { try await store.restore(fixture.installation) }
    #expect(try String(contentsOf: fixture.texture, encoding: .utf8) == "outside edit")
    let link = fixture.source.appendingPathComponent("content/textures/link.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.texture)
    await #expect(throws: EngineError.self) { try await store.importFolder(fixture.source) }
}

@Test func playHistoryPersistsSessionBoundaries() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABHistory-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PlayHistoryStore(directory: root)
    var session = PlaySession(placeID: "1818", name: "Test", startedAt: Date(timeIntervalSinceReferenceDate: 100))
    session.endedAt = Date(timeIntervalSinceReferenceDate: 200)
    try await store.save([session])
    #expect(try await store.load() == [session])
}

@Test func discordIPCHandshakePingAndActivityAreAcknowledged() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/tmp/ab-ipc-\(UUID().uuidString.prefix(8))")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    #expect(fd >= 0)
    defer { Darwin.close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let path = Array(root.appendingPathComponent("discord-ipc-0").path.utf8) + [0]
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
    let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    #expect(bound == 0)
    #expect(Darwin.listen(fd, 1) == 0)
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    let game = GameDetails(placeID: "1818", universeID: 111, name: "Test", creator: "Creator", playing: nil,
                           iconURL: URL(string: "https://tr.rbxcdn.com/test.png"), fetchedAt: Date())
    let scenarios: [(DiscordPresenceOptions, GameDetails?)] = [
        (.init(), nil), (.init(showPlayTime: false), nil), (.init(), nil),
        (.init(showArtwork: true), game),
        (.init(showGameActivity: false, showArtwork: true), game),
        (.init(showGameButton: false), game),
        (.init(showArtwork: true), nil)
    ]
    // The client uses blocking socket I/O. Its peer must not depend on the same
    // cooperative Swift executor, which may have only one worker available in CI.
    let server = AsyncThrowingStream<Bool, any Error> { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let success = try { () throws -> Bool in
                    let connection = Darwin.accept(fd, nil, nil)
                    guard connection >= 0 else { throw FeatureError.message("Mock Discord accept timed out") }
                    defer { Darwin.close(connection) }
                    var timeout = timeval(tv_sec: 3, tv_usec: 0)
                    _ = setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
                    func read(_ size: Int) throws -> Data {
                        var bytes = Data(count: size)
                        var offset = 0
                        try bytes.withUnsafeMutableBytes { pointer in
                            while offset < size {
                                let count = Darwin.recv(connection, pointer.baseAddress!.advanced(by: offset), size - offset, 0)
                                guard count > 0 else { throw FeatureError.message("Mock read failed") }; offset += count
                            }
                        }
                        return bytes
                    }
                    func receive() throws -> [String: Any] {
                        let header = try read(8)
                        let count = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
                        guard count < 65_536 else { throw FeatureError.message("Bad mock frame") }
                        return try JSONSerialization.jsonObject(with: read(Int(count))) as? [String: Any] ?? [:]
                    }
                    func send(_ data: Data, opcode: UInt32 = 1) throws {
                        let frame = DiscordPresenceClient.frame(opcode: opcode, data: data)
                        let count = frame.withUnsafeBytes { Darwin.send(connection, $0.baseAddress, $0.count, 0) }
                        guard count == frame.count else { throw FeatureError.message("Mock write failed") }
                    }
                    let handshake = try receive()
                    guard handshake["client_id"] as? String == "123" else { return false }
                    try send(Data(#"{"evt":"READY"}"#.utf8))
                    for index in scenarios.indices {
                        let showTime = index != 1
                        let command = try receive()
                        let args = try #require(command["args"] as? [String: Any])
                        let activity = try #require(args["activity"] as? [String: Any])
                        #expect(command["cmd"] as? String == "SET_ACTIVITY")
                        #expect(activity["details"] as? String == (index == 4 ? "Playing Roblox" : "Test"))
                        #expect(activity["state"] as? String == (index == 3 ? "by Creator" : "Playing with AppleBlox Native"))
                        #expect((activity["assets"] != nil) == (index == 3))
                        if index == 3 {
                            #expect((activity["assets"] as? [String: String])?["large_image"] == "https://tr.rbxcdn.com/test.png")
                        }
                        #expect((activity["timestamps"] != nil) == showTime)
                        if showTime {
                            let timestamps = try #require(activity["timestamps"] as? [String: Any])
                            #expect(timestamps["start"] as? Int == 1_700_000_000)
                        }
                        let buttonURL = (activity["buttons"] as? [[String: String]])?.first?["url"]
                        #expect(buttonURL == ([4, 5].contains(index) ? nil : "https://www.roblox.com/games/1818/"))
                        try send(Data("{}".utf8), opcode: 3)
                        _ = try receive() // PONG
                        try send(JSONSerialization.data(withJSONObject: ["nonce": command["nonce"] ?? ""]))
                    }
                    return true
                }()
                continuation.yield(success)
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
    let client = DiscordPresenceClient(socketRoots: [root.path])
    let session = PlaySession(placeID: "1818", name: "Test", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
    for (options, metadata) in scenarios {
        try await client.update(clientID: "123", session: session, running: true, options: options, game: metadata)
        // Unchanged payloads should not send another command; metadata/options changes above must send immediately.
        try await client.update(clientID: "123", session: session, running: true, options: options, game: metadata)
    }
    for try await success in server { #expect(success) }
    await client.disconnect()
}

private struct ModFixture {
    let root: URL
    let source: URL
    let texture: URL
    let installation: RobloxInstallation
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ABMods-\(UUID())")
        source = root.appendingPathComponent("Test Mod")
        let app = root.appendingPathComponent("Roblox.app")
        texture = app.appendingPathComponent("Contents/Resources/content/textures/test.png")
        let executable = app.appendingPathComponent("Contents/MacOS/RobloxPlayer")
        for directory in [texture.deletingLastPathComponent(), executable.deletingLastPathComponent(), source.appendingPathComponent("content/textures")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try Data("original".utf8).write(to: texture)
        try Data("replacement".utf8).write(to: source.appendingPathComponent("content/textures/test.png"))
        let info = ["CFBundleIdentifier": RobloxInstallation.bundleIdentifier, "CFBundleExecutable": "RobloxPlayer", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        installation = try RobloxInstallation.inspect(app)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func customFontFamilyKeepsWeightsAndReplacesAssets() throws {
    let original = Data(#"{"name":"Test","faces":[{"weight":400,"style":"normal","assetId":"old"},{"weight":700,"style":"normal","assetId":"other"}]}"#.utf8)
    let data = try ContentModStore.fontFamily(original, asset: "rbxasset://fonts/Test.ttf")
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let faces = try #require(object["faces"] as? [[String: Any]])
    #expect(faces.count == 2)
    #expect(faces[1]["weight"] as? Int == 700)
    #expect(faces.allSatisfy { $0["assetId"] as? String == "rbxasset://fonts/Test.ttf" })
}

@Test func historyIgnoresOlderWriteRevisions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABHistoryRevision-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PlayHistoryStore(directory: root)
    let session = PlaySession(placeID: "1818", name: "Latest")
    try await store.save([session], revision: 2)
    try await store.save([], revision: 1)
    #expect(try await store.load() == [session])
}

@Test func logRotationCapturesTheFirstJoinInANewFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABRotation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let reader = PlayerLogReader()
    #expect(try await reader.poll(directory: root).isEmpty)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let log = root.appendingPathComponent("Player_new.log")
    try Data("[FLog::Output] ! Joining game 'test' place 1818 at 127.0.0.1\n".utf8).write(to: log)
    #expect(try await reader.poll(directory: root) == [.joining("1818")])
}

@Test func quitLauncherPreferenceMigratesAndPersists() throws {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(FeatureSettings())) as? [String: Any])
    object.removeValue(forKey: "quitLauncherWithPlayer")
    object["trackHistory"] = true
    object["discordClientID"] = "12345"
    let previous = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(!previous.quitLauncherWithPlayer)
    #expect(previous.trackHistory)
    #expect(previous.discordClientID == "12345")
    var config = NativeConfiguration()
    config.features = previous
    config.features.quitLauncherWithPlayer = true
    let restored = try JSONDecoder().decode(NativeConfiguration.self, from: JSONEncoder().encode(config)).validated()
    #expect(restored == config)
    object["quitLauncherWithPlayer"] = "true"
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

@Test func returnToWebsitePreferenceMigratesIndependentlyOfQuit() throws {
    var settings = FeatureSettings()
    settings.quitLauncherWithPlayer = true
    settings.trackHistory = true
    var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
    old.removeValue(forKey: "returnToWebsite")
    let migrated = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: old)).validated()
    #expect(!migrated.returnToWebsite)
    #expect(migrated.quitLauncherWithPlayer)
    #expect(migrated.trackHistory)
    for quit in [false, true] {
        var config = NativeConfiguration()
        config.features = migrated
        config.features.returnToWebsite = true
        config.features.quitLauncherWithPlayer = quit
        #expect(try JSONDecoder().decode(NativeConfiguration.self, from: JSONEncoder().encode(config)).validated() == config)
    }
    old["returnToWebsite"] = "true"
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: old))
    }
}

@Test func discordPlayTimePreferenceDefaultsOnForExistingUsers() throws {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(FeatureSettings())) as? [String: Any])
    object.removeValue(forKey: "discordPlayTime")
    object["discordPresence"] = true
    var settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: object)).validated()
    #expect(settings.discordPlayTime)
    #expect(settings.discordPresence)
    settings.discordPlayTime = false
    #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
}
