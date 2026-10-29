import Foundation
import Testing
@testable import AppleBloxCore

private struct ScanFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABModScan-\(UUID())")
    var source: URL { root.appendingPathComponent("Source") }
    var library: URL { root.appendingPathComponent("mods") }
    init() throws {
        try FileManager.default.createDirectory(at: source.appendingPathComponent("content/textures"), withIntermediateDirectories: true)
        try Data("texture".utf8).write(to: source.appendingPathComponent("content/textures/test.png"))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func modRescanUpdatesCountsAndPreservesPackIdentityAndChoices() async throws {
    let fixture = try ScanFixture(); defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.library)
    var mod = try await store.importFolder(fixture.source)
    mod.enabled = false; mod.name = "My color"; mod.iconColorHex = "#0A84FF"
    let package = await store.packageURL(mod)
    let extra = package.appendingPathComponent("content/textures/new.png")
    let bytes = Data("new texture".utf8)
    try bytes.write(to: extra)
    let scan = try await store.scan([mod])
    #expect(scan.mods[0].id == mod.id)
    #expect(scan.mods[0].name == mod.name)
    #expect(scan.mods[0].iconColorHex == mod.iconColorHex)
    #expect(!scan.mods[0].enabled)
    #expect(scan.mods[0].fileCount == 2)
    #expect(scan.issues.isEmpty && scan.overlaps.isEmpty)
    #expect(try Data(contentsOf: extra) == bytes)
    #expect(!FileManager.default.fileExists(atPath: fixture.library.appendingPathComponent("backups").path))
    try FileManager.default.removeItem(at: extra)
    #expect(try await store.scan(scan.mods).mods[0].fileCount == 1)
}

@Test func modRescanDetectsCaseInsensitiveOverlapsAndTracksEnabledSelection() async throws {
    let fixture = try ScanFixture(); defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.library)
    let first = try await store.importFolder(fixture.source)
    try FileManager.default.removeItem(at: fixture.source.appendingPathComponent("content/textures/test.png"))
    try Data("another".utf8).write(to: fixture.source.appendingPathComponent("content/textures/TEST.PNG"))
    var second = try await store.importFolder(fixture.source)
    second.enabled = false
    let scan = try await store.scan([first, second])
    #expect(scan.overlaps.count == 1)
    #expect(scan.activeConflicts(in: [first, second]).isEmpty)
    #expect(!scan.blocksApplying([first, second]))
    second.enabled = true
    let active = scan.activeConflicts(in: [first, second])
    #expect(active.count == 1)
    #expect(Set(active[0].modIDs) == [first.id, second.id])
    #expect(scan.blocksApplying([first, second]))
    #expect(!scan.blocksApplying([first]))
}

@Test func modRescanReportsMissingAndInvalidPacksWithoutRemovingRecords() async throws {
    let fixture = try ScanFixture(); defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.library)
    var first = try await store.importFolder(fixture.source)
    var second = try await store.importFolder(fixture.source)
    let firstPackage = await store.packageURL(first)
    let secondPackage = await store.packageURL(second)
    try FileManager.default.removeItem(at: firstPackage)
    try Data("unsupported".utf8).write(to: secondPackage.appendingPathComponent("content/textures/script.lua"))
    let scan = try await store.scan([first, second])
    #expect(scan.mods == [first, second])
    #expect(Set(scan.issues.map(\.id)) == [first.id, second.id])
    #expect(scan.blocksApplying([first, second]))
    first.enabled = false; second.enabled = false
    #expect(!scan.blocksApplying([first, second]))
    #expect(try Data(contentsOf: secondPackage.appendingPathComponent("content/textures/script.lua")) == Data("unsupported".utf8))
    await #expect(throws: (any Error).self) { try await store.checkedPackageURL(first) }
}

@Test func modRescanRejectsSymlinkedPackageParents() async throws {
    let fixture = try ScanFixture(); defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.library)
    let mod = try await store.importFolder(fixture.source)
    let packages = fixture.library.appendingPathComponent("packages")
    let outside = fixture.root.appendingPathComponent("outside")
    try FileManager.default.moveItem(at: packages, to: outside)
    try FileManager.default.createSymbolicLink(at: packages, withDestinationURL: outside)
    let scan = try await store.scan([mod])
    #expect(scan.issues.count == 1)
    #expect(scan.blocksApplying([mod]))
    await #expect(throws: EngineError.self) { try await store.checkedPackageURL(mod) }
    #expect(try String(contentsOf: outside.appendingPathComponent("\(mod.id.uuidString)/content/textures/test.png"), encoding: .utf8) == "texture")
}

@Test func modRescanDoesNotRediscoverRemovedOrUnregisteredFolders() async throws {
    let fixture = try ScanFixture(); defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.library)
    let mod = try await store.importFolder(fixture.source)
    let unused = fixture.library.appendingPathComponent("packages/\(UUID())")
    try FileManager.default.createDirectory(at: unused, withIntermediateDirectories: true)
    try Data("not a mod".utf8).write(to: unused.appendingPathComponent("script.lua"))
    let retained = try await store.scan([mod])
    #expect(retained.mods.count == 1 && retained.issues.isEmpty)
    let removed = try await store.scan([])
    #expect(removed.mods.isEmpty && removed.issues.isEmpty && removed.overlaps.isEmpty)
    #expect(FileManager.default.fileExists(atPath: (await store.packageURL(mod)).path))
}

@Test func modRescanCancellationAndDuplicateRecordsFailWithoutWrites() async throws {
    let fixture = try ScanFixture(); defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.library)
    let mod = try await store.importFolder(fixture.source)
    await #expect(throws: FeatureError.self) { try await store.scan([mod, mod]) }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await store.scan([mod])
    }
    do { _ = try await task.value; Issue.record("Cancelled scan should throw") }
    catch { #expect(error is CancellationError) }
    let scan = try await store.scan([mod])
    #expect(scan.mods == [mod] && scan.issues.isEmpty)
}

@Test func modRescanDoesNotAcceptPartialEnumerationOfUnreadableFolders() async throws {
    let fixture = try ScanFixture(); defer { fixture.remove() }
    let store = ContentModStore(directory: fixture.library)
    let mod = try await store.importFolder(fixture.source)
    let hidden = (await store.packageURL(mod)).appendingPathComponent("content/private")
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    try Data("unreadable".utf8).write(to: hidden.appendingPathComponent("test.png"))
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: hidden.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hidden.path) }
    let scan = try await store.scan([mod])
    #expect(scan.issues.count == 1)
    #expect(scan.mods[0].fileCount == mod.fileCount)
}
