import Foundation
import Testing
@testable import AppleBloxCore

private func legacyData(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
private func legacyConversion(_ object: [String: Any]) throws -> LegacyProfileConversion {
    try JSONDecoder().decode(LegacyEngineProfile.self, from: legacyData(object)).converted()
}
private let globalLegacy: [String: String] = ["name": "Imported global", "type": "default"]

@Test func legacyImportPreservesValidDisabledRowsAndReportsSkippedRows() throws {
    let converted = try legacyConversion(["name": "Legacy", "type": "game", "games": ["0001818"], "flags": [
        ["flag": "FFlagDebugSkyGray", "enabled": true, "value": "True"],
        ["flag": "DFIntTextureQualityOverride", "enabled": false, "value": "2"],
        ["flag": "Unknown", "enabled": false, "value": NSNull()],
        ["flag": "DFFlagDisableDPIScale", "enabled": false, "value": "invalid"]]])
    #expect(converted.profile.customFlags == ["FFlagDebugSkyGray": .boolean(true)])
    #expect(converted.profile.disabledCustomFlags == ["DFIntTextureQualityOverride": .integer(2)])
    #expect(converted.profile.includesSelectedProfile && converted.placeIDs == ["1818"])
    #expect(converted.warnings.count == 2 && converted.warnings[0].contains("Unknown"))
}

@Test func legacyImportValidatesKindsAssignmentsAndDuplicateRows() throws {
    let global = try legacyConversion(["name": "Global", "type": "default", "games": ["1818"], "flags": []])
    #expect(global.placeIDs.isEmpty && global.warnings.count == 1 && !global.profile.includesSelectedProfile)
    let inferred = try legacyConversion(["name": "Old game", "games": ["1818"], "flags": []])
    #expect(inferred.kind == .game && inferred.placeIDs == ["1818"])
    for object: [String: Any] in [
        ["name": "Bad", "type": "unsupported", "flags": []],
        ["name": "Bad", "type": "game", "games": [], "flags": []],
        ["name": "Bad", "type": "game", "games": ["1818", "01818"], "flags": []],
        ["name": "Bad", "type": "game", "games": ["https://evil.test"], "flags": []],
        ["name": "Bad", "flags": [["flag": "Unknown", "enabled": true, "value": true]]],
        ["name": "Bad", "flags": [["flag": "FFlagDebugSkyGray", "enabled": true, "value": NSNull()]]],
        ["name": "Bad", "flags": [["flag": "FFlagDebugSkyGray", "enabled": true, "value": true], ["flag": "FFlagDebugSkyGray", "enabled": false, "value": false]]]
    ] { #expect(throws: (any Error).self) { try legacyConversion(object) } }
}

@Test func importedGameFlagsOverlaySelectedGlobalAndExplicitSelectionUsesOwnFlags() throws {
    var configuration = EngineConfiguration()
    configuration.profiles[0].renderer = .metal
    configuration.profiles[0].customFlags = ["FFlagDebugSkyGray": .boolean(false), "DFIntTextureQualityOverride": .integer(1)]
    let imported = try legacyConversion(["name": "Game", "type": "game", "games": ["1818"], "flags": [
        ["flag": "FFlagDebugSkyGray", "enabled": true, "value": true],
        ["flag": "DFIntTextureQualityOverride", "enabled": false, "value": 3]]])
    configuration.profiles.append(imported.profile)
    let flags = try configuration.resolvedFlags(for: imported.profile.id)
    #expect(flags["FFlagDebugGraphicsPreferMetal"] == .boolean(true))
    #expect(flags["FFlagDebugSkyGray"] == .boolean(true))
    #expect(flags["DFIntTextureQualityOverride"] == .integer(1))
    configuration.selectedProfileID = imported.profile.id
    #expect(try configuration.resolvedFlags() == imported.profile.resolvedFlags())
    #expect(throws: EngineError.self) { try configuration.resolvedFlags(for: UUID()) }
    var profileJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(imported.profile)) as? [String: Any])
    profileJSON.removeValue(forKey: "includesSelectedProfile")
    #expect(try !JSONDecoder().decode(EngineProfile.self, from: JSONSerialization.data(withJSONObject: profileJSON)).includesSelectedProfile)
}

@Test func legacyBatchReviewPreservesExistingGameIdentityAndRequiresExplicitApply() throws {
    var settings = NativeConfiguration()
    let game = try GameShortcut(name: "My custom title", placeID: "1818")
    settings.shortcuts = [game]
    let original = settings
    let file = try legacyData(["name": "Game overlay", "type": "game", "games": ["1818", "123"], "flags": []])
    let plan = try LegacyProfileImportPlan(files: [file], configuration: settings)
    #expect(settings == original && settings.engine.profiles.count == 1)
    #expect(plan.updatedAssignments == 1 && plan.addedGames == 1)
    let result = try plan.applying(to: settings)
    #expect(result.shortcuts[0].id == game.id && result.shortcuts[0].name == "My custom title")
    #expect(result.shortcuts[0].engineProfileID == result.engine.profiles.last?.id)
    #expect(!result.engine.applyOnLaunch && result.engine.selectedProfileID == original.engine.selectedProfileID)
    settings.appearance.reduceMotion.toggle()
    #expect(throws: FeatureError.self) { try plan.applying(to: settings) }
}

@Test func legacyBatchFailuresPreserveConfigurationAndRejectAmbiguousAssignments() throws {
    let original = NativeConfiguration()
    let valid = try legacyData(["name": "Good", "type": "game", "games": ["1818"], "flags": []])
    let invalid = try legacyData(["name": "Bad", "type": "default", "flags": [["flag": "Unknown", "enabled": true, "value": true]]])
    #expect(throws: EngineError.self) { try LegacyProfileImportPlan(files: [valid, invalid], configuration: original) }
    #expect(throws: FeatureError.self) { try LegacyProfileImportPlan(files: [valid, valid], configuration: original) }
    #expect(original == NativeConfiguration())
    let global = try legacyData(["name": "Global", "type": "default", "flags": []])
    let plan = try LegacyProfileImportPlan(files: [global], configuration: original)
    #expect(plan.addedGames == 0 && plan.updatedAssignments == 0)
    #expect(try plan.applying(to: original).shortcuts.isEmpty)
}

@Test func legacyBatchAndProfileBoundsPreventUnboundedReviews() throws {
    let settings = NativeConfiguration()
    let valid = try legacyData(["name": "Bounded", "flags": []])
    for files in [[], Array(repeating: valid, count: 51), [Data(repeating: 32, count: 1_048_577)], Array(repeating: Data(repeating: 32, count: 1_000_000), count: 9)] {
        #expect(throws: EngineError.self) { try LegacyProfileImportPlan(files: files, configuration: settings) }
    }
    #expect(throws: EngineError.self) { try legacyConversion(["name": String(repeating: "a", count: 81), "flags": []]) }
    #expect(throws: FeatureError.self) { try legacyConversion(["name": "Bad", "flags": [["flag": String(repeating: "a", count: 257), "enabled": false, "value": 1]]]) }
}
