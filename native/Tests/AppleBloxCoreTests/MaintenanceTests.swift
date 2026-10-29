import Foundation
import Testing
@testable import AppleBloxCore

@Test func diagnosticsOnlyIncludesFixedSupportFields() {
    var report = DiagnosticsReport()
    report.appVersion = "0.1.0-dev.12"; report.appBuild = "24"
    report.architecture = "arm64"
    report.systemVersion = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)
    report.playerVersion = "0.744.0.7441080"
    report.gameCount = 3; report.profileCount = 2; report.modCount = 4; report.metadataCount = 5
    #expect(report.text.contains("App: 0.1.0-dev.12 (24)"))
    #expect(report.text.contains("macOS: 27.0.1"))
    #expect(report.text.contains("Player version: 0.744.0.7441080"))
    #expect(report.text.contains("Cached game details: 5"))
    #expect(!report.text.contains("http") && !report.text.contains("/Users/"))
    report.appVersion = "0.7.1\nprivate data"
    report.appBuild = "24\nprivate data"
    report.playerVersion = "/Users/private data"
    report.architecture = "private data"
    report.gameCount = -1
    #expect(!report.text.contains("private data"))
    #expect(report.text.contains("Saved games: 0"))
    report.appVersion = "0.7.1\n"
    #expect(report.text.contains("App: Development"))
}

private func cachedDetailsDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABMaintenance-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let game = GameDetails(placeID: "1818", universeID: 111, name: "Cached title", creator: "Creator", playing: nil, iconURL: nil, fetchedAt: Date())
    try JSONEncoder().encode([game]).write(to: root.appendingPathComponent("game-details-cache.json"))
    return root
}

@Test func clearingCacheRemovesMemoryAndDiskEntriesOnly() async throws {
    let root = try cachedDetailsDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let unrelated = ["native-settings.json", "mods/backup.txt", "engine-backups/backup.txt", "play-history.json"]
    for name in unrelated {
        let file = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preserve".utf8).write(to: file)
    }
    let catalog = GameCatalog(directory: root, fetch: { _ in throw URLError(.notConnectedToInternet) })
    #expect(await catalog.cachedGameCount == 1)
    #expect(try await catalog.clearCache() == 1)
    #expect(await catalog.cachedGameCount == 0)
    #expect(await catalog.cachedGame(for: "1818") == nil)
    let reloaded = GameCatalog(directory: root, fetch: { _ in throw URLError(.notConnectedToInternet) })
    #expect(await reloaded.cachedGameCount == 0)
    await #expect(throws: (any Error).self) { try await reloaded.game(for: "1818") }
    for name in unrelated { #expect(try Data(contentsOf: root.appendingPathComponent(name)) == Data("preserve".utf8)) }
}

@Test func clearingAbsentCacheIsIdempotentAndDoesNotCreateDataFolders() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABEmptyCache-\(UUID())")
    let catalog = GameCatalog(directory: root)
    #expect(try await catalog.clearCache() == 0)
    #expect(try await catalog.clearCache() == 0)
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

private actor CacheLookupGate {
    var requests = 0
    var waiting: CheckedContinuation<Data, Never>?
    var started: CheckedContinuation<Void, Never>?
    func fetch(_ url: URL) async -> Data {
        requests += 1
        started?.resume(); started = nil
        return await withCheckedContinuation { waiting = $0 }
    }
    func waitForRequest() async {
        if requests == 0 { await withCheckedContinuation { started = $0 } }
    }
    func release() { waiting?.resume(returning: Data(#"{"universeId":111}"#.utf8)); waiting = nil }
}

@Test func clearingCacheInvalidatesAnAlreadyRunningLookup() async throws {
    let gate = CacheLookupGate()
    let catalog = GameCatalog(fetch: { await gate.fetch($0) })
    let request = Task { try await catalog.game(for: "1818") }
    await gate.waitForRequest()
    try await catalog.clearCache()
    await gate.release()
    do { _ = try await request.value; Issue.record("Pre-clear lookup must not return or repopulate stale details") }
    catch { #expect(error is CancellationError) }
    #expect(await catalog.cachedGameCount == 0)
    #expect(await gate.requests == 1)
}

@Test func failedCacheClearPreservesMemoryAndDisk() async throws {
    let root = try cachedDetailsDirectory()
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path); try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent("game-details-cache.json")
    let bytes = try Data(contentsOf: cache)
    let catalog = GameCatalog(directory: root)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    await #expect(throws: (any Error).self) { try await catalog.clearCache() }
    #expect(await catalog.cachedGameCount == 1)
    #expect(try Data(contentsOf: cache) == bytes)
}

@Test func clearingCacheRejectsSymlinkedFilesWithoutFollowingThem() async throws {
    let root = try cachedDetailsDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent("game-details-cache.json")
    let catalog = GameCatalog(directory: root)
    let outside = root.appendingPathComponent("unrelated.json")
    let bytes = Data("preserve external data".utf8)
    try bytes.write(to: outside)
    try FileManager.default.removeItem(at: cache)
    try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: outside)
    await #expect(throws: FeatureError.self) { try await catalog.clearCache() }
    #expect(await catalog.cachedGameCount == 1)
    #expect(try Data(contentsOf: outside) == bytes)
}
