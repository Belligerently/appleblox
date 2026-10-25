import Foundation
import Testing
@testable import AppleBloxCore

@Test func newGraphicsPresetsDefaultToNoOverridesAndMigrateExistingQuality() throws {
    let profile = EngineProfile(name: "Default")
    #expect(try profile.resolvedFlags().isEmpty)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    for key in ["separateQualityAndDistance", "objectDetailDistance", "disableVoxelShadows"] { object.removeValue(forKey: key) }
    object["graphicsQuality"] = 12
    var migrated = try JSONDecoder().decode(EngineProfile.self, from: JSONSerialization.data(withJSONObject: object)).validated()
    #expect(migrated.separateQualityAndDistance)
    #expect(migrated.objectDetailDistance == .automatic && !migrated.disableVoxelShadows)
    #expect(try migrated.resolvedFlags()["DFIntDebugFRMQualityLevelOverride"] == .integer(12))
    migrated.separateQualityAndDistance = false
    let saved = try JSONDecoder().decode(EngineProfile.self, from: JSONEncoder().encode(migrated))
    #expect(saved.graphicsQuality == 12 && !saved.separateQualityAndDistance)
    #expect(try saved.resolvedFlags()["DFIntDebugFRMQualityLevelOverride"] == nil)
    object.removeValue(forKey: "graphicsQuality")
    #expect(try JSONDecoder().decode(EngineProfile.self, from: JSONSerialization.data(withJSONObject: object)).resolvedFlags().isEmpty)
}

@Test func qualityAndObjectDistanceAreIndependentAndCustomOverridesStillWin() throws {
    let keys = ["DFIntCSGLevelOfDetailSwitchingDistance", "DFIntCSGLevelOfDetailSwitchingDistanceL12",
                "DFIntCSGLevelOfDetailSwitchingDistanceL23", "DFIntCSGLevelOfDetailSwitchingDistanceL34"]
    for enabled in [false, true] {
        for distance in ObjectDetailDistance.allCases {
            var profile = EngineProfile(name: "Distance")
            profile.separateQualityAndDistance = enabled
            profile.graphicsQuality = 10
            profile.objectDetailDistance = distance
            let flags = try profile.resolvedFlags()
            #expect(flags["DFIntDebugFRMQualityLevelOverride"] == (enabled ? .integer(10) : nil))
            for key in keys { #expect(flags[key] == distance.studs.map(FlagValue.integer)) }
            #expect(try FastFlags.validate(flags) == flags)
            profile.customFlags = [keys[0]: .integer(42)]
            #expect(try profile.resolvedFlags()[keys[0]] == .integer(42))
            profile.customFlags = [:]
            profile.disabledCustomFlags = [keys[0]: .integer(42)]
            #expect(try profile.resolvedFlags()[keys[0]] == distance.studs.map(FlagValue.integer))
        }
    }
}

@Test func voxelShadowPresetUsesOnlyAllowedFlagAndCanBeOverridden() throws {
    var profile = EngineProfile(name: "Shadows")
    profile.disableVoxelShadows = true
    #expect(try profile.resolvedFlags() == ["DFFlagDebugPauseVoxelizer": .boolean(true)])
    profile.customFlags = ["DFFlagDebugPauseVoxelizer": .boolean(false)]
    #expect(try profile.resolvedFlags() == ["DFFlagDebugPauseVoxelizer": .boolean(false)])
    profile.disableVoxelShadows = false
    profile.customFlags = [:]
    #expect(try profile.resolvedFlags().isEmpty)
}

@Test func experimentalVulkanUsesOriginalMappingWithoutChangingOtherRenderers() throws {
    var profile = EngineProfile(name: "Renderer")
    for renderer in GraphicsRenderer.allCases {
        profile.renderer = renderer
        let flags = try profile.resolvedFlags()
        #expect(try FastFlags.validate(flags) == flags)
        #expect(flags["FFlagDebugGraphicsPreferVulkan"] == (renderer == .vulkan ? .boolean(true) : nil))
        #expect(flags["FFlagDebugGraphicsDisableMetal"] == ([.vulkan, .openGL].contains(renderer) ? .boolean(true) : nil))
        #expect(flags["FFlagDebugGraphicsPreferMetal"] == (renderer == .metal ? .boolean(true) : nil))
        #expect(flags["FFlagDebugGraphicsPreferOpenGL"] == (renderer == .openGL ? .boolean(true) : nil))
        #expect(try JSONDecoder().decode(EngineProfile.self, from: JSONEncoder().encode(profile)) == profile)
    }
}

@Test func newGraphicsPresetsRejectInvalidSavedValuesBeforeApplying() throws {
    let profile = EngineProfile(name: "Validation")
    let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    for (key, value) in [("disableVoxelShadows", "true"), ("separateQualityAndDistance", "yes"),
                         ("objectDetailDistance", "unsupported"), ("renderer", "direct3d12")] {
        var object = original
        object[key] = value
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EngineProfile.self, from: JSONSerialization.data(withJSONObject: object)) }
    }
    var missing = profile
    missing.separateQualityAndDistance = true
    #expect(throws: EngineError.self) { try missing.validated() }
    for quality in [0, 22, Int.max] {
        missing.graphicsQuality = quality
        #expect(throws: EngineError.self) { try missing.resolvedFlags() }
    }
}

@Test func legacyResolutionLaunchPlansPreserveLinksAsSingleArguments() throws {
    let urls: [URL?] = [nil, URL(string: "roblox://experiences/start?placeId=1818"),
                       URL(string: "roblox-player:1+launchmode:play+gameinfo:test-only&literal=$value")]
    for url in urls {
        for newInstance in [false, true] {
            let ordinary = try PlayerLaunchPlan(url: url, legacyResolution: false, newInstance: newInstance, playerRunning: true)
            #expect(ordinary.urlToOpen == url && ordinary.arguments.isEmpty)
            let legacy = try PlayerLaunchPlan(url: url, legacyResolution: true, newInstance: newInstance, playerRunning: false)
            #expect(legacy.urlToOpen == nil)
            #expect(legacy.arguments == ["-AppleMagnifiedMode", "YES"] + (url.map { [$0.absoluteString] } ?? []))
            #expect(legacy.createsNewInstance == newInstance)
        }
    }
    let normalized = try PlayerLaunchPlan(url: URL(string: "appleblox-native://play?placeId=1818"), legacyResolution: true, newInstance: false, playerRunning: false)
    #expect(normalized.arguments.last == "roblox://experiences/start?placeId=1818")
}

@Test func legacyResolutionRequiresFreshLaunchAndRejectsUnrelatedURLs() throws {
    #expect(throws: FeatureError.self) { try PlayerLaunchPlan(legacyResolution: true, newInstance: false, playerRunning: true) }
    #expect(try PlayerLaunchPlan(legacyResolution: true, newInstance: true, playerRunning: true).createsNewInstance)
    for string in ["https://evil.test/", "file:///tmp/script", "javascript:alert(1)", "appleblox-native://play?placeId=bad"] {
        #expect(throws: (any Error).self) { try PlayerLaunchPlan(url: URL(string: string), legacyResolution: true, newInstance: false, playerRunning: false) }
    }
}

@Test func legacyResolutionMigratesOffAndPersistsWithoutChangingOtherSettings() throws {
    var features = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
    #expect(!features.legacyResolution)
    let original = features
    features.legacyResolution = true
    let loaded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(features)).validated()
    #expect(loaded == features)
    features.legacyResolution = false
    #expect(features == original)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"legacyResolution":"yes"}"#.utf8)) }
}

@Test func graphicsClusterCanBeSavedAppliedAndRestoredWithExactOriginalBytes() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABGraphics-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Roblox.app")
    let executable = app.appendingPathComponent("Contents/MacOS/RobloxPlayer")
    let target = app.appendingPathComponent("Contents/MacOS/ClientSettings/ClientAppSettings.json")
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let info = ["CFBundleIdentifier": RobloxInstallation.bundleIdentifier, "CFBundlePackageType": "APPL", "CFBundleExecutable": "RobloxPlayer"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
    let installation = try RobloxInstallation.inspect(app)
    let original = Data("original bytes\n".utf8)
    try original.write(to: target)
    var configuration = NativeConfiguration()
    configuration.engine.profiles[0].renderer = .vulkan
    configuration.engine.profiles[0].disableVoxelShadows = true
    configuration.engine.profiles[0].separateQualityAndDistance = true
    configuration.engine.profiles[0].graphicsQuality = 8
    configuration.engine.profiles[0].objectDetailDistance = .far
    configuration.features.legacyResolution = true
    let settingsStore = ConfigurationStore(directory: root.appendingPathComponent("settings"))
    try settingsStore.save(configuration)
    let saved = try settingsStore.load()
    #expect(saved == configuration)
    let flags = try #require(saved.engine.selectedProfile).resolvedFlags()
    let store = ClientSettingsStore(directory: root.appendingPathComponent("backups"))
    try await store.apply(flags, to: installation)
    #expect(try FastFlags.parse(String(contentsOf: target, encoding: .utf8)) == flags)
    try await store.restore(installation)
    #expect(try Data(contentsOf: target) == original)
}
