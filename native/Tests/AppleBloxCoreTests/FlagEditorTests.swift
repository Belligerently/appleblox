import Foundation
import Testing
@testable import AppleBloxCore

@Test func flagEditorMigratesOldProfilesAndPersistsDisabledValues() throws {
    var profile = EngineProfile(name: "Existing")
    profile.customFlags = ["FFlagDebugSkyGray": .boolean(false)]
    var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    old.removeValue(forKey: "disabledCustomFlags")
    let migrated = try JSONDecoder().decode(EngineProfile.self, from: JSONSerialization.data(withJSONObject: old)).validated()
    #expect(migrated.disabledCustomFlags.isEmpty)
    #expect(migrated.customFlags == profile.customFlags)
    var draft = FlagEditorDraft(profile: migrated)
    draft.rows[0].enabled = false
    let saved = try draft.applying(to: migrated)
    #expect(saved.customFlags.isEmpty)
    #expect(saved.disabledCustomFlags == profile.customFlags)
    #expect(try saved.resolvedFlags().isEmpty)
    #expect(try FastFlags.parse(draft.enabledJSON()).isEmpty)
    let restored = try JSONDecoder().decode(EngineProfile.self, from: JSONEncoder().encode(saved)).validated()
    #expect(restored == saved)
    var reopened = FlagEditorDraft(profile: restored)
    #expect(!reopened.rows[0].enabled)
    #expect(reopened.rows[0].value == "false")
    reopened.rows[0].enabled = true
    #expect(try reopened.applying(to: restored).resolvedFlags() == profile.customFlags)
}

@Test func disablingCustomOverrideRestoresPresetAndKeepsItsValue() throws {
    var profile = EngineProfile(name: "Preset")
    profile.graySky = true
    profile.customFlags = ["FFlagDebugSkyGray": .boolean(false)]
    var draft = FlagEditorDraft(profile: profile)
    #expect(try draft.applying(to: profile).resolvedFlags()["FFlagDebugSkyGray"] == .boolean(false))
    draft.rows[0].enabled = false
    let saved = try draft.applying(to: profile)
    #expect(try saved.resolvedFlags()["FFlagDebugSkyGray"] == .boolean(true))
    #expect(saved.disabledCustomFlags["FFlagDebugSkyGray"] == .boolean(false))
}

@Test func flagEditorAddsTypedRowsAndRejectsDuplicatesAndUnknownNames() throws {
    var draft = FlagEditorDraft(profile: EngineProfile(name: "Test"))
    try draft.add("FFlagDebugSkyGray")
    try draft.add("DFIntTextureQualityOverride")
    #expect(draft.rows.first { $0.name == "FFlagDebugSkyGray" }?.isBoolean == true)
    #expect(draft.rows.first { $0.name == "DFIntTextureQualityOverride" }?.value == "0")
    #expect(throws: EngineError.self) { try draft.add("FFlagDebugSkyGray") }
    #expect(throws: EngineError.self) { try draft.add("UnknownFlag") }
    #expect(draft.rows.count == 2)
    draft.rows[0].value = "2147483648"
    #expect(throws: EngineError.self) { try draft.applying(to: EngineProfile(name: "Test")) }
    draft.rows[0].value = " -2147483648 "
    #expect(try draft.rows[0].validatedValue() == .integer(Int(Int32.min)))
    draft.rows[0].value = "1.5"
    draft.rows[0].enabled = false
    #expect(throws: EngineError.self) { try draft.applying(to: EngineProfile(name: "Test")) }
}

@Test func importingEnabledJSONPreservesDisabledRowsAndStableIdentity() throws {
    var profile = EngineProfile(name: "Import")
    profile.customFlags = ["FFlagDebugSkyGray": .boolean(true)]
    profile.disabledCustomFlags = ["DFIntTextureQualityOverride": .integer(2), "FIntFRMMaxGrassDistance": .integer(42)]
    var draft = FlagEditorDraft(profile: profile)
    let textureID = try #require(draft.rows.first { $0.name == "DFIntTextureQualityOverride" }?.id)
    let grass = try #require(draft.rows.first { $0.name == "FIntFRMMaxGrassDistance" })
    try draft.replaceEnabledJSON(#"{"DFIntTextureQualityOverride":"3"}"#)
    #expect(draft.rows.count == 2)
    #expect(draft.rows.first { $0.id == textureID }?.enabled == true)
    #expect(draft.rows.first { $0.id == textureID }?.value == "3")
    #expect(draft.rows.first { $0.id == grass.id } == grass)
    #expect(try draft.applying(to: profile).customFlags == ["DFIntTextureQualityOverride": .integer(3)])
    let unchanged = draft
    for invalid in ["{", #"{"Unknown":true}"#, #"{"DFIntTextureQualityOverride":true}"#] {
        #expect(throws: EngineError.self) { try draft.replaceEnabledJSON(invalid) }
        #expect(draft == unchanged)
    }
}

@Test func flagSearchAndBulkRemovalKeepUnselectedRows() throws {
    var profile = EngineProfile(name: "Search")
    profile.customFlags = ["FFlagDebugSkyGray": .boolean(true), "DFIntTextureQualityOverride": .integer(3)]
    profile.disabledCustomFlags = ["FIntFRMMaxGrassDistance": .integer(42)]
    var draft = FlagEditorDraft(profile: profile)
    #expect(draft.matching("  SKY  ").count == 1)
    #expect(draft.matching("42").count == 1)
    #expect(draft.matching("no match").isEmpty)
    let selected = Set(draft.rows.filter { $0.name != "FIntFRMMaxGrassDistance" }.map(\.id))
    draft.remove(selected)
    #expect(draft.rows.count == 1)
    #expect(!draft.rows[0].enabled)
    #expect(try draft.applying(to: profile).disabledCustomFlags == profile.disabledCustomFlags)
}

@Test func invalidDisabledFlagsPreserveExistingSettings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ABFlagEditor-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationStore(directory: directory)
    let original = NativeConfiguration()
    try store.save(original)
    let bytes = try Data(contentsOf: store.fileURL)
    var changed = original
    changed.engine.profiles[0].disabledCustomFlags = ["UnknownFlag": .boolean(true)]
    #expect(throws: EngineError.self) { try store.save(changed) }
    #expect(try Data(contentsOf: store.fileURL) == bytes)
    changed = original
    changed.engine.profiles[0].customFlags = ["FFlagDebugSkyGray": .boolean(true)]
    changed.engine.profiles[0].disabledCustomFlags = ["FFlagDebugSkyGray": .boolean(false)]
    #expect(throws: EngineError.self) { try store.save(changed) }
    #expect(try store.load() == original)
}

@Test func duplicateDraftRowsFailWithoutTrapping() throws {
    let row = FlagEditorRow(name: "FFlagDebugSkyGray", value: .boolean(true))
    var draft = FlagEditorDraft(profile: EngineProfile(name: "Test"))
    draft.rows = [row, row]
    #expect(throws: EngineError.self) { try draft.replaceEnabledJSON("{}") }
    #expect(throws: EngineError.self) { try draft.applying(to: EngineProfile(name: "Test")) }
}
