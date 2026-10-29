import Foundation
import Testing
@testable import AppleBloxCore

private func themeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ABThemes-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
@Test func nativeThemesValidateColorsContrastAndFormat() throws {
    var theme = NativeThemeDocument()
    #expect(try theme.validated() == theme)
    #expect(try NativeThemeDocument.contrast("#000000", "#FFFFFF") == 21)
    theme.accent = "#0A84FF"; #expect(try theme.validated().accent == "#0A84FF")
    theme.accent = "#FFFFFF"; #expect(throws: (any Error).self) { try theme.validated() }
    theme = NativeThemeDocument(); theme.darkCard = "#EEEEEE"
    #expect(throws: (any Error).self) { try theme.validated() }
    theme = NativeThemeDocument(); theme.lightBackground = "#111111"
    #expect(throws: (any Error).self) { try theme.validated() }
    theme = NativeThemeDocument(); theme.accent = "red"
    #expect(throws: (any Error).self) { try theme.validated() }
    theme = NativeThemeDocument(); theme.version = 2
    #expect(throws: (any Error).self) { try theme.validated() }
    theme = NativeThemeDocument(); theme.name = "bad\nname"
    #expect(throws: (any Error).self) { try theme.validated() }
}
@Test func nativeThemeImportRejectsExecutableUnknownAndOversizedInput() throws {
    for bytes in [Data("body { color:red }".utf8), Data(repeating: 32, count: 32_769), Data("<Theme/>".utf8)] {
        #expect(throws: (any Error).self) { try NativeThemeStore.decode(bytes) }
    }
    var object = try #require(JSONSerialization.jsonObject(with: NativeThemeDocument().json) as? [String: Any])
    object["assetURL"] = "https://example.com/private"
    #expect(throws: (any Error).self) { try NativeThemeStore.decode(JSONSerialization.data(withJSONObject: object)) }
}
@Test func themeLibraryPreservesDuplicateNamesAndReloadsLocalEdits() async throws {
    let root = try themeRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = NativeThemeStore(dataDirectory: root)
    var theme = NativeThemeDocument()
    let first = try await store.save(theme), second = try await store.save(theme)
    #expect(first != second)
    theme.name = "Edited"; theme.accent = "#2463AA"
    try await store.save(theme, id: first)
    #expect(try await store.read(first) == theme)
    let file = try await store.file(first)
    theme.name = "External edit"; try theme.json.write(to: file)
    let reloaded = NativeThemeStore(dataDirectory: root)
    #expect(try await reloaded.read(first).name == "External edit")
    #expect(try await reloaded.list().records.count == 2)
    let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
@Test func themeRemovalIsRecoverableAndDoesNotRemoveUnrelatedFiles() async throws {
    let root = try themeRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = NativeThemeStore(dataDirectory: root)
    let theme = NativeThemeDocument(); let id = try await store.save(theme)
    let folder = try await store.folder()
    try Data("preserve".utf8).write(to: folder.appendingPathComponent("notes.txt"))
    try await store.remove(id)
    #expect(try await store.list().records.isEmpty)
    let removed = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("removed"), includingPropertiesForKeys: nil)
    #expect(removed.count == 1)
    #expect(try NativeThemeStore.decode(Data(contentsOf: removed[0])) == theme)
    #expect(try String(contentsOf: folder.appendingPathComponent("notes.txt"), encoding: .utf8) == "preserve")
}
@Test func invalidLinkedAndFutureThemeFilesArePreservedAndSkipped() async throws {
    let root = try themeRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = NativeThemeStore(dataDirectory: root)
    let folder = try await store.folder()
    let source = root.appendingPathComponent("source.json"); try NativeThemeDocument().json.write(to: source)
    let link = folder.appendingPathComponent("\(UUID()).json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    let id = UUID(); let corrupt = folder.appendingPathComponent("\(id).json")
    let bytes = Data("preserve broken file".utf8); try bytes.write(to: corrupt)
    let snapshot = try await store.list(); #expect(snapshot.skipped == 2 && snapshot.records.isEmpty)
    await #expect(throws: (any Error).self) { try await store.save(NativeThemeDocument(), id: id) }
    #expect(try Data(contentsOf: corrupt) == bytes)
    #expect(try NativeThemeStore.decode(Data(contentsOf: source)) == NativeThemeDocument())
}
@Test func themeImportsCopySourceAndRespectLibraryLimit() async throws {
    let root = try themeRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = NativeThemeStore(dataDirectory: root)
    let source = root.appendingPathComponent("theme.json"); let bytes = try NativeThemeDocument().json; try bytes.write(to: source)
    try await store.importFile(source)
    for _ in 0..<49 { try await store.save(NativeThemeDocument()) }
    await #expect(throws: (any Error).self) { try await store.importFile(source) }
    await #expect(throws: (any Error).self) { try await store.save(NativeThemeDocument(), id: UUID()) }
    #expect(try Data(contentsOf: source) == bytes)
    #expect(try await store.list().records.count == 50)
}
@Test func customPalettesMigrateAndPersistWithoutLeakingIntoSupportSummary() throws {
    let old = Data(#"{"theme":"Dark","reduceMotion":true}"#.utf8)
    let appearance = try JSONDecoder().decode(AppearanceSettings.self, from: old)
    #expect(appearance.customTheme == nil && appearance.theme == .dark && appearance.reduceMotion)
    var config = NativeConfiguration(); var theme = NativeThemeDocument(); theme.name = "PRIVATE-THEME-NAME"
    config.appearance.customTheme = theme; config.appearance.customThemeID = UUID()
    let reloaded = try JSONDecoder().decode(NativeConfiguration.self, from: JSONEncoder().encode(config)).validated()
    #expect(reloaded.appearance == config.appearance)
    let text = String(decoding: try JSONEncoder().encode(SupportSettingsSummary(configuration: config)), as: UTF8.self)
    #expect(!text.contains("PRIVATE-THEME-NAME") && !text.contains("#B12646"))
}
