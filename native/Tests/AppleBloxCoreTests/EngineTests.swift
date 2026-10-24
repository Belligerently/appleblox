import Foundation
import Testing
@testable import AppleBloxCore

@Test func legacySettingsGainAStableDefaultEngineProfile() throws {
    let legacy = Data(#"{"version":1,"shortcuts":[],"customRobloxPath":"/Applications/Roblox.app"}"#.utf8)
    let settings = try JSONDecoder().decode(NativeConfiguration.self, from: legacy).validated()
    #expect(settings.engine == EngineConfiguration())
    #expect(settings.customRobloxPath == "/Applications/Roblox.app")
    #expect(!settings.engine.applyOnLaunch)
    #expect(try settings.engine.selectedProfile?.resolvedFlags().isEmpty == true)
    #expect(try JSONDecoder().decode(NativeConfiguration.self, from: JSONEncoder().encode(settings)) == settings)
}

@Test func presetsResolveAndCustomValuesOverrideThem() throws {
    var profile = EngineProfile(name: "  My graphics  ")
    profile.renderer = .openGL
    profile.graphicsQuality = 12
    profile.textureQuality = 2
    profile.fullResolution = true
    profile.graySky = true
    profile.customFlags = ["FFlagDebugSkyGray": .string("False"), "DFIntDebugFRMQualityLevelOverride": .string("8")]
    let flags = try profile.resolvedFlags()
    #expect(flags["FFlagDebugGraphicsDisableMetal"] == .boolean(true))
    #expect(flags["FFlagDebugGraphicsPreferOpenGL"] == .boolean(true))
    #expect(flags["FFlagDebugGraphicsPreferMetal"] == nil)
    #expect(flags["DFIntDebugFRMQualityLevelOverride"] == .integer(8))
    #expect(flags["DFIntTextureQualityOverride"] == .integer(2))
    #expect(flags["DFFlagTextureQualityOverrideEnabled"] == .boolean(true))
    #expect(flags["FFlagDebugSkyGray"] == .boolean(false))
    #expect(try profile.validated().name == "My graphics")
    #expect(try FastFlags.parse(FastFlags.json(flags)) == flags)
    profile.renderer = .metal
    #expect(try profile.resolvedFlags()["FFlagDebugGraphicsDisableMetal"] == nil)
}

@Test func invalidFlagsAndProfilesAreRejected() throws {
    for json in ["[]", "{", #"{"UnknownFlag":true}"#, #"{"FFlagDebugSkyGray":3}"#,
                 #"{"DFIntTextureQualityOverride":true}"#, #"{"DFIntTextureQualityOverride":1.5}"#,
                 #"{"FFlagDebugSkyGray":null}"#, #"{"DFIntTextureQualityOverride":2147483648}"#] {
        #expect(throws: EngineError.self) { try FastFlags.parse(json) }
    }
    var settings = NativeConfiguration()
    settings.engine.profiles[0].graphicsQuality = 22
    #expect(throws: EngineError.self) { try settings.validated() }
    settings = NativeConfiguration()
    settings.engine.selectedProfileID = UUID()
    #expect(throws: EngineError.self) { try settings.validated() }
    settings = NativeConfiguration()
    settings.engine.profiles.append(settings.engine.profiles[0])
    #expect(throws: EngineError.self) { try settings.validated() }
}

@Test func applyingRepeatedlyKeepsExactOriginalBackup() async throws {
    let fixture = try EngineFixture()
    defer { fixture.remove() }
    let original = Data("original settings, even if not JSON\n".utf8)
    try original.write(to: fixture.target)
    let store = ClientSettingsStore(directory: fixture.backups)
    try await store.apply(["FFlagDebugSkyGray": .boolean(true)], to: fixture.installation)
    #expect(await store.hasBackup(for: fixture.installation))
    try await store.apply(["DFIntTextureQualityOverride": .integer(3)], to: fixture.installation)
    #expect(try FastFlags.parse(String(contentsOf: fixture.target, encoding: .utf8)) == ["DFIntTextureQualityOverride": .integer(3)])
    try await store.restore(fixture.installation)
    #expect(try Data(contentsOf: fixture.target) == original)
    #expect(await !store.hasBackup(for: fixture.installation))
}

@Test func restoreRemovesAFileThatDidNotExistOriginally() async throws {
    let fixture = try EngineFixture()
    defer { fixture.remove() }
    let store = ClientSettingsStore(directory: fixture.backups)
    try await store.apply([:], to: fixture.installation)
    #expect(FileManager.default.fileExists(atPath: fixture.target.path))
    try await store.restore(fixture.installation)
    #expect(!FileManager.default.fileExists(atPath: fixture.target.path))
}

@Test func outsideChangesAndCorruptBackupsAreNeverOverwritten() async throws {
    let fixture = try EngineFixture()
    defer { fixture.remove() }
    let store = ClientSettingsStore(directory: fixture.backups)
    try await store.apply([:], to: fixture.installation)
    let outside = Data("{\"outside\":true}".utf8)
    try outside.write(to: fixture.target)
    await #expect(throws: EngineError.self) { try await store.restore(fixture.installation) }
    await #expect(throws: EngineError.self) { try await store.apply([:], to: fixture.installation) }
    #expect(try Data(contentsOf: fixture.target) == outside)
    let backup = try #require(FileManager.default.contentsOfDirectory(at: fixture.backups, includingPropertiesForKeys: nil).first)
    try Data("bad backup".utf8).write(to: backup)
    await #expect(throws: EngineError.self) { try await store.restore(fixture.installation) }
    #expect(try Data(contentsOf: backup) == Data("bad backup".utf8))
    #expect(try Data(contentsOf: fixture.target) == outside)
}

@Test func symlinkedClientSettingsCannotRedirectWrites() async throws {
    let fixture = try EngineFixture()
    defer { fixture.remove() }
    let destination = fixture.root.appendingPathComponent("outside.json")
    let original = Data("untouched".utf8)
    try original.write(to: destination)
    try FileManager.default.createSymbolicLink(at: fixture.target, withDestinationURL: destination)
    let store = ClientSettingsStore(directory: fixture.backups)
    await #expect(throws: EngineError.self) { try await store.apply([:], to: fixture.installation) }
    #expect(try Data(contentsOf: destination) == original)
    #expect(await !store.hasBackup(for: fixture.installation))
}

private struct EngineFixture {
    let root: URL
    let installation: RobloxInstallation
    let target: URL
    var backups: URL { root.appendingPathComponent("backups") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppleBloxEngineTests-\(UUID())")
        let app = root.appendingPathComponent("Roblox.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        target = macOS.appendingPathComponent("ClientSettings/ClientAppSettings.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("RobloxPlayer")
        try Data("test fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let plist = ["CFBundleIdentifier": RobloxInstallation.bundleIdentifier, "CFBundleExecutable": "RobloxPlayer", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        installation = try RobloxInstallation.inspect(app)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
