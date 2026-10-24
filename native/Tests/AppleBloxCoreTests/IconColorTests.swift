import CoreText
import Foundation
import Testing
@testable import AppleBloxCore

@Test func iconColorValidatesAndNormalizesHex() throws {
    let blue = try IconColor(hex: " 0a84ff ")
    #expect(blue.hex == "#0A84FF")
    #expect(blue.red == 10 && blue.green == 132 && blue.blue == 255)
    for invalid in ["", "#FFF", "#12345678", "#GGGGGG", "##123456", "１２３４５６"] {
        #expect(throws: FeatureError.self) { try IconColor(hex: invalid) }
    }
}

@Test func coloredFontPreservesOutlinesAndHasCorrectChecksums() throws {
    let original = try iconTestFont()
    let blue = try IconColor(hex: "#0A84FF")
    let tinted = try IconFontColorizer.colorize(original, color: blue)
    let before = fontTables(original)
    let after = fontTables(tinted)
    #expect(after["glyf"]?.bytes == before["glyf"]?.bytes)
    #expect(after["cmap"]?.bytes == before["cmap"]?.bytes)
    #expect(after["maxp"]?.bytes == before["maxp"]?.bytes)
    #expect(Array(try #require(after["CPAL"]).bytes.suffix(4)) == [255, 132, 10, 255])
    let glyphs = read16(try #require(before["maxp"]).bytes, 4)
    let colr = try #require(after["COLR"]).bytes
    #expect(read16(colr, 2) == glyphs)
    #expect(colr.count == 14 + glyphs * 10)
    #expect(IconFontColorizer.checksum(tinted) == 0xB1B0AFBA)
    for (tag, entry) in after {
        var bytes = entry.bytes
        if tag == "head" { bytes.replaceSubrange(8..<12, with: [0, 0, 0, 0]) }
        #expect(IconFontColorizer.checksum(bytes) == entry.checksum, "Invalid checksum for \(tag)")
    }
    let descriptors = CTFontManagerCreateFontDescriptorsFromData(tinted as CFData)
    #expect(CFArrayGetCount(descriptors) == 1)
    let retinted = try IconFontColorizer.colorize(tinted, color: IconColor(hex: "#B12646"))
    #expect(fontTables(retinted).count == after.count)
    #expect(IconFontColorizer.checksum(retinted) == 0xB1B0AFBA)
}

@Test func malformedIconFontsFailWithoutTrapping() throws {
    let original = try iconTestFont()
    var badOffset = original
    badOffset.replaceSubrange(20..<24, with: [255, 255, 255, 255])
    var badCount = original
    badCount.replaceSubrange(4..<6, with: [255, 255])
    let color = try IconColor(hex: "#FFFFFF")
    for data in [Data(), Data(original.prefix(11)), Data(original.prefix(50)), badOffset, badCount, Data(repeating: 0, count: 80)] {
        #expect(throws: FeatureError.self) { try IconFontColorizer.colorize(data, color: color) }
    }
}

@Test func iconFamilyPreservesFacesAndRejectsUnexpectedAssets() throws {
    let data = iconFamily()
    let result = try #require(JSONSerialization.jsonObject(with: IconFontColorizer.family(data)) as? [String: Any])
    #expect(result["loadStrategy"] as? String == "sameFamilyOnly")
    let faces = try #require(result["faces"] as? [[String: Any]])
    #expect(faces[0]["weight"] as? Int == 400)
    #expect(faces[1]["weight"] as? Int == 700)
    #expect((faces[1]["assetId"] as? String)?.hasSuffix("BuilderIcons-Filled.otf") == true)
    let invalid = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "BuilderIcons-Regular.ttf", with: "Unexpected.ttf").utf8)
    #expect(throws: FeatureError.self) { try IconFontColorizer.family(invalid) }
}

@Test func iconModStagesDisabledAndRestoresOriginalResources() async throws {
    let fixture = try IconFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = ContentModStore(directory: fixture.root.appendingPathComponent("mods"))
    let original = try Data(contentsOf: fixture.family)
    let mod = try await store.importIconColor(IconColor(hex: "#0A84FF"), installation: fixture.installation)
    #expect(!mod.enabled)
    #expect(mod.iconColorHex == "#0A84FF" && mod.fileCount == 3)
    #expect(try Data(contentsOf: fixture.family) == original)
    try await store.apply([mod], to: fixture.installation)
    #expect(try Data(contentsOf: fixture.family) == original)
    var enabled = mod
    enabled.enabled = true
    try await store.apply([enabled], to: fixture.installation)
    #expect(try Data(contentsOf: fixture.family) != original)
    let coloredFont = fixture.family.deletingLastPathComponent().appendingPathComponent("Font/BuilderIcons-Regular.otf")
    #expect(FileManager.default.fileExists(atPath: coloredFont.path))
    try await store.restore(fixture.installation)
    #expect(try Data(contentsOf: fixture.family) == original)
    #expect(!FileManager.default.fileExists(atPath: coloredFont.path))
}

@Test func failedIconGenerationLeavesNoPartialPackage() async throws {
    let fixture = try IconFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let font = fixture.family.deletingLastPathComponent().appendingPathComponent("Font/BuilderIcons-Filled.ttf")
    try Data("invalid font".utf8).write(to: font)
    let directory = fixture.root.appendingPathComponent("mods")
    let store = ContentModStore(directory: directory)
    await #expect(throws: (any Error).self) { try await store.importIconColor(IconColor(hex: "#FFFFFF"), installation: fixture.installation) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test func iconGenerationRejectsSymlinkedSourceFonts() async throws {
    let fixture = try IconFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let font = fixture.family.deletingLastPathComponent().appendingPathComponent("Font/BuilderIcons-Regular.ttf")
    let outside = fixture.root.appendingPathComponent("outside.ttf")
    try FileManager.default.moveItem(at: font, to: outside)
    try FileManager.default.createSymbolicLink(at: font, withDestinationURL: outside)
    let directory = fixture.root.appendingPathComponent("mods")
    let store = ContentModStore(directory: directory)
    await #expect(throws: (any Error).self) { try await store.importIconColor(IconColor(hex: "#FFFFFF"), installation: fixture.installation) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test func oldModRecordsStillDecodeAndIconColorsRoundTrip() throws {
    let id = UUID()
    let old = Data("{\"id\":\"\(id)\",\"name\":\"Old mod\",\"enabled\":true,\"fileCount\":1}".utf8)
    var mod = try JSONDecoder().decode(ContentMod.self, from: old)
    #expect(mod.iconColorHex == nil)
    mod.iconColorHex = "#B12646"
    var config = NativeConfiguration()
    config.features.mods = [mod]
    let encoded = try JSONEncoder().encode(config)
    #expect(try JSONDecoder().decode(NativeConfiguration.self, from: encoded).validated() == config)
    config.features.mods[0].iconColorHex = "invalid"
    #expect(throws: (any Error).self) { try config.validated() }
}

private struct FontEntry {
    let bytes: Data
    let checksum: UInt32
}
private func read16(_ data: Data, _ at: Int) -> Int { (Int(data[at]) << 8) | Int(data[at + 1]) }
private func read32(_ data: Data, _ at: Int) -> UInt32 {
    (UInt32(data[at]) << 24) | (UInt32(data[at + 1]) << 16) | (UInt32(data[at + 2]) << 8) | UInt32(data[at + 3])
}
private func fontTables(_ data: Data) -> [String: FontEntry] {
    var result: [String: FontEntry] = [:]
    for index in 0..<read16(data, 4) {
        let entry = 12 + index * 16
        let tag = String(decoding: data[entry..<entry + 4], as: UTF8.self)
        let offset = Int(read32(data, entry + 8)), length = Int(read32(data, entry + 12))
        result[tag] = FontEntry(bytes: data.subdata(in: offset..<offset + length), checksum: read32(data, entry + 4))
    }
    return result
}
private func put32(_ value: UInt32, _ data: inout Data, _ at: Int) {
    data.replaceSubrange(at..<at + 4, with: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
}
private func iconTestFont() throws -> Data {
    let font = CTFontCreateWithName("ArialMT" as CFString, 12, nil)
    let tags = try #require(CTFontCopyAvailableTables(font, CTFontTableOptions(rawValue: 0)))
    var tables: [String: Data] = [:]
    // CoreText returns unboxed numeric tags, not Objective-C objects.
    for index in 0..<CFArrayGetCount(tags) {
        let tag = UInt32(UInt(bitPattern: CFArrayGetValueAtIndex(tags, index)))
        var value = tag.bigEndian
        let name = withUnsafeBytes(of: &value) { String(decoding: $0, as: UTF8.self) }
        if let data = CTFontCopyTable(font, tag, CTFontTableOptions(rawValue: 0)) { tables[name] = data as Data }
    }
    #expect(tables["glyf"] != nil)
    let names = tables.keys.sorted()
    var data = Data(repeating: 0, count: 12 + names.count * 16)
    put32(0x00010000, &data, 0)
    data[4] = UInt8(names.count >> 8); data[5] = UInt8(truncatingIfNeeded: names.count)
    for (index, name) in names.enumerated() {
        let table = try #require(tables[name])
        let entry = 12 + index * 16
        data.replaceSubrange(entry..<entry + 4, with: name.utf8)
        put32(UInt32(data.count), &data, entry + 8); put32(UInt32(table.count), &data, entry + 12)
        data.append(table)
        while data.count % 4 != 0 { data.append(0) }
    }
    return data
}
private func iconFamily() -> Data {
    Data(#"{"name":"Builder Icons","loadStrategy":"sameFamilyOnly","faces":[{"name":"Regular","weight":400,"style":"normal","assetId":"rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/Font/BuilderIcons-Regular.ttf"},{"name":"Bold","weight":700,"style":"normal","assetId":"rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/Font/BuilderIcons-Filled.ttf"}]}"#.utf8)
}
private struct IconFixture {
    let root: URL
    let installation: RobloxInstallation
    let family: URL
    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("IconModTests-\(UUID())")
        let app = root.appendingPathComponent("Roblox.app")
        let contents = app.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("MacOS/RobloxPlayer")
        try Data("test fixture".utf8).write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let plist = ["CFBundleIdentifier": RobloxInstallation.bundleIdentifier, "CFBundleExecutable": "RobloxPlayer", "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let icons = contents.appendingPathComponent("Resources/" + IconFontColorizer.resourcePath)
        try fm.createDirectory(at: icons.appendingPathComponent("Font"), withIntermediateDirectories: true)
        let font = try iconTestFont()
        for name in ["Regular", "Filled"] { try font.write(to: icons.appendingPathComponent("Font/BuilderIcons-\(name).ttf")) }
        family = icons.appendingPathComponent("BuilderIcons.json")
        try iconFamily().write(to: family)
        installation = try RobloxInstallation.inspect(app)
    }
}
