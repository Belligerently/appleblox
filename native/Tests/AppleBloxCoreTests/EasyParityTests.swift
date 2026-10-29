import Foundation
import Testing
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import AppleBloxCore

private func easyRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ABEasy-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
@Test func clearHistoryPreservesPrivateRecoveryAndRejectsOlderWrites() async throws {
    let root = try easyRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = PlayHistoryStore(directory: root)
    let sessions = [PlaySession(placeID: "1818", name: "Test")]
    try await store.save(sessions, revision: 1)
    let original = try Data(contentsOf: root.appendingPathComponent("play-history.json"))
    let recovery = try #require(try await store.clear(revision: 3))
    #expect(try Data(contentsOf: recovery) == original)
    #expect((try FileManager.default.attributesOfItem(atPath: recovery.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try await store.load().isEmpty)
    try await store.save(sessions, revision: 2)
    #expect(try await store.load().isEmpty)
    try await store.save(sessions, revision: 4)
    #expect(try await store.load() == sessions)
    await #expect(throws: (any Error).self) { try await store.clear(revision: 4) }
    let reset = NativeResetService(dataDirectory: root)
    #expect(try await reset.prepare().itemNames.contains("history-recovery"))
}
@Test func clearHistoryRejectsCorruptAndLinkedFilesWithoutReplacingThem() async throws {
    let root = try easyRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = PlayHistoryStore(directory: root)
    let file = root.appendingPathComponent("play-history.json")
    let bad = Data("broken".utf8)
    try bad.write(to: file)
    await #expect(throws: (any Error).self) { try await store.clear(revision: 1) }
    #expect(try Data(contentsOf: file) == bad)
    try FileManager.default.removeItem(at: file)
    let target = root.appendingPathComponent("unrelated.json")
    try Data("[]".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    await #expect(throws: (any Error).self) { try await store.clear(revision: 2) }
    #expect(try Data(contentsOf: target) == Data("[]".utf8))
}
@Test func clearMissingHistoryCreatesAnEmptyStoreAndAllowsFutureSessions() async throws {
    let root = try easyRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = PlayHistoryStore(directory: root)
    #expect(try await store.clear(revision: 1) == nil)
    #expect(try await store.load().isEmpty)
    try await store.save([PlaySession(placeID: "1", name: "Future")], revision: 2)
    #expect(try await store.load().count == 1)
}
@Test func desktopShortcutsUseNativeLinksAndNeverReplaceExistingFiles() throws {
    let root = try easyRoot(); defer { try? FileManager.default.removeItem(at: root) }
    for place in [String?.none, "0001818"] {
        let bytes = try LaunchShortcut.data(placeID: place)
        let plist = try #require(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: String])
        let value = try #require(plist["URL"])
        let url = try #require(URL(string: value))
        let link = try LaunchLink(url)
        #expect(link.isLauncherOnly == (place == nil))
        #expect(link.placeID == (place == nil ? nil : "1818"))
    }
    let target = root.appendingPathComponent("Launch.webloc")
    try LaunchShortcut.save(to: target)
    let bytes = try Data(contentsOf: target)
    #expect(throws: (any Error).self) { try LaunchShortcut.save(placeID: "1", to: target) }
    #expect(try Data(contentsOf: target) == bytes)
    #expect(throws: (any Error).self) { try LaunchShortcut.data(placeID: "../evil") }
    for url in ["appleblox-native://launch?placeId=1", "appleblox-native://user@launch", "appleblox-native://launch/path", "appleblox-native://launch#fragment"] {
        #expect(throws: (any Error).self) { try LaunchLink(URL(string: url)!) }
    }
}
@Test func flagRenameKeepsIdentityValueAndEnabledStateAndRejectsConflicts() throws {
    let profile = EngineProfile(name: "Test")
    var draft = FlagEditorDraft(profile: profile)
    try draft.add("FFlagDebugSkyGray")
    try draft.add("FFlagDebugGraphicsPreferMetal")
    draft.rows[0].enabled = false
    let row = draft.rows[0]
    try draft.rename(row.id, to: "DFFlagDisableDPIScale")
    let renamed = try #require(draft.rows.first { $0.id == row.id })
    #expect(renamed.value == row.value && renamed.enabled == row.enabled)
    let before = draft
    #expect(throws: (any Error).self) { try draft.rename(row.id, to: "Unknown") }
    #expect(throws: (any Error).self) { try draft.rename(row.id, to: "FIntFRMMaxGrassDistance") }
    #expect(draft == before)
    let other = try #require(draft.rows.first { $0.id != row.id })
    #expect(throws: (any Error).self) { try draft.rename(row.id, to: other.name) }
    #expect(draft == before)
}
@Test func flagBulkEnableAndSelectedExportIncludeDisabledValuesWithoutMutatingThem() throws {
    var profile = EngineProfile(name: "Test")
    profile.customFlags = ["FFlagDebugSkyGray": .boolean(true)]
    profile.disabledCustomFlags = ["FIntFRMMaxGrassDistance": .integer(250)]
    var draft = FlagEditorDraft(profile: profile)
    let ids = Set(draft.rows.map(\.id))
    let before = draft
    let values = try FastFlags.parse(draft.selectedJSON(ids))
    #expect(values.count == 2 && values["FIntFRMMaxGrassDistance"] == .integer(250))
    #expect(draft == before)
    draft.setEnabled(true, for: ids)
    #expect(try draft.applying(to: profile).customFlags.count == 2)
    draft.setEnabled(false, for: ids)
    #expect(try draft.applying(to: profile).disabledCustomFlags.count == 2)
    #expect(try FastFlags.parse(draft.enabledJSON()).isEmpty)
}
private func tinyPNG() throws -> Data {
    let pixels = Data(repeating: 160, count: 32 * 32 * 4)
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 128,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}
@Test func modPreviewsAreBoundedLocalAndCountAllBytesIncludingNonimages() async throws {
    let root = try easyRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("content/textures"), withIntermediateDirectories: true)
    let png = try tinyPNG()
    for i in 0..<4 { try png.write(to: source.appendingPathComponent("content/textures/\(i).png")) }
    let text = Data("{}".utf8)
    try text.write(to: source.appendingPathComponent("content/test.json"))
    let store = ContentModStore(directory: root.appendingPathComponent("mods"))
    let mod = try await store.importFolder(source)
    let summary = try await store.visualSummary(mod)
    #expect(summary.byteCount == Int64(4 * png.count + text.count))
    #expect(summary.fileCount == 5 && summary.thumbnails.count == 3)
    for thumbnail in summary.thumbnails {
        let decoded = try #require(CGImageSourceCreateWithData(thumbnail.png as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        #expect((props[kCGImagePropertyPixelWidth] as? Int ?? 0) <= 192)
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("mods/backups").path))
}
@Test func modPreviewsSkipMalformedImagesAndRejectLinkedPacks() async throws {
    let root = try easyRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source/content")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("not an image".utf8).write(to: source.appendingPathComponent("invalid.png"))
    let store = ContentModStore(directory: root.appendingPathComponent("mods"))
    let mod = try await store.importFolder(source.deletingLastPathComponent())
    #expect(try await store.visualSummary(mod).thumbnails.isEmpty)
    let file = await store.packageURL(mod).appendingPathComponent("content/invalid.png")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: source.appendingPathComponent("invalid.png"))
    await #expect(throws: (any Error).self) { try await store.visualSummary(mod) }
}
