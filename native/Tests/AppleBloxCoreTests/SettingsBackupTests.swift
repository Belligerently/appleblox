import Foundation
import Testing
@testable import AppleBloxCore

private struct BackupFixture {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ABSettings-\(UUID())")
    var data: URL { root.appendingPathComponent("data") }
    var source: URL { root.appendingPathComponent("backup.json") }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func prepare(current: NativeConfiguration, imported: NativeConfiguration) throws -> SettingsBackupService {
        try ConfigurationStore(directory: data).save(current)
        try SettingsBackupDocument(configuration: imported).data.write(to: source)
        return SettingsBackupService(directory: data)
    }
}
@Test func settingsBackupRoundTripPreservesProfilesAndAssignmentsButExcludesLocalIdentity() throws {
    var config = NativeConfiguration()
    config.customRobloxPath = "/private/path/Roblox.app"
    config.features.accounts = [.init(id: 42, name: "PrivateAccount", displayName: "Private Display")]
    config.features.selectedAccountID = 42
    config.features.mods = [.init(name: "Private Mod", fileCount: 1)]
    config.shortcuts = [try GameShortcut(name: "My Game", placeID: "123")]
    config.shortcuts[0].engineProfileID = config.engine.selectedProfileID
    config.engine.profiles[0].customFlags = ["FFlagDebugGraphicsPreferMetal": .boolean(true)]
    config.engine.profiles[0].disabledCustomFlags = ["FIntDebugForceMSAASamples": .integer(4)]
    let data = try SettingsBackupDocument(configuration: config).data
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("PrivateAccount"))
    #expect(!text.contains("/private/path"))
    #expect(!text.contains("Private Mod"))
    let read = try JSONDecoder().decode(SettingsBackupDocument.self, from: data).validated()
    #expect(read.configuration.shortcuts == config.shortcuts)
    #expect(read.configuration.engine == config.engine)
}
@Test func settingsRestorePreservesLocalResourcesDisablesAutomationAndCreatesPrivateRecovery() async throws {
    let f = BackupFixture(); defer { f.cleanup() }
    var current = NativeConfiguration()
    current.customRobloxPath = "/Applications/Roblox.app"
    current.features.accounts = [.init(id: 1, name: "Local", displayName: "Local")]
    current.features.selectedAccountID = 1
    current.features.mods = [.init(name: "Local Mod", fileCount: 1)]
    var imported = NativeConfiguration()
    imported.shortcuts = [try GameShortcut(name: "Imported", placeID: "123")]
    imported.appearance.reduceMotion = true
    imported.engine.applyOnLaunch = true
    imported.features.discordPresence = true
    imported.features.automaticUpdates = true
    imported.features.experimentalFPSWorkaround = true
    imported.features.serverJoinedNotifications = true
    imported.features.trackHistory = true
    let service = try f.prepare(current: current, imported: imported)
    let original = try Data(contentsOf: ConfigurationStore(directory: f.data).fileURL)
    let plan = try await service.prepare(from: f.source, current: current)
    let saved = try await service.restore(plan, current: current)
    #expect(try Data(contentsOf: saved) == original)
    #expect((try FileManager.default.attributesOfItem(atPath: saved.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let next = try ConfigurationStore(directory: f.data).load()
    #expect(next.features.accounts == current.features.accounts)
    #expect(next.features.mods == current.features.mods)
    #expect(next.features.selectedAccountID == 1)
    #expect(next.customRobloxPath == current.customRobloxPath)
    #expect(next.shortcuts == imported.shortcuts)
    #expect(next.appearance.reduceMotion)
    #expect(!next.engine.applyOnLaunch && !next.features.discordPresence && !next.features.automaticUpdates)
    #expect(!next.features.experimentalFPSWorkaround && !next.features.serverJoinedNotifications && !next.features.trackHistory)
    // New recovery directories remain accepted by the reset inventory and are archived with other data.
    let reset = NativeResetService(dataDirectory: f.data)
    #expect(try await reset.prepare().itemNames.contains("settings-recovery"))
}
@Test func settingsRestoreRefusesStaleMemoryAndDiskWithoutReplacingSettings() async throws {
    let f = BackupFixture(); defer { f.cleanup() }
    let current = NativeConfiguration()
    let service = try f.prepare(current: current, imported: current)
    let plan = try await service.prepare(from: f.source, current: current)
    var changed = current; changed.appearance.reduceMotion = true
    await #expect(throws: SettingsBackupError.self) { try await service.restore(plan, current: changed) }
    try ConfigurationStore(directory: f.data).save(changed)
    await #expect(throws: SettingsBackupError.self) { try await service.restore(plan, current: current) }
    #expect(try ConfigurationStore(directory: f.data).load() == changed)
}
@Test func settingsBackupRejectsMalformedUnsupportedOversizedAndLinkedInputs() async throws {
    let f = BackupFixture(); defer { f.cleanup() }
    let current = NativeConfiguration()
    let service = try f.prepare(current: current, imported: current)
    let original = try Data(contentsOf: f.source)
    for bad in [Data("{".utf8), Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 9").utf8), Data(repeating: 65, count: SettingsBackupService.limit + 1)] {
        try bad.write(to: f.source)
        await #expect(throws: (any Error).self) { try await service.prepare(from: f.source, current: current) }
    }
    try original.write(to: f.source)
    let link = f.root.appendingPathComponent("linked.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.source)
    await #expect(throws: (any Error).self) { try await service.prepare(from: link, current: current) }
    #expect(try ConfigurationStore(directory: f.data).load() == current)
}
@Test func settingsBackupExportNeverReplacesAnExistingDestination() async throws {
    let f = BackupFixture(); defer { f.cleanup() }
    let current = NativeConfiguration()
    let service = try f.prepare(current: current, imported: current)
    let destination = f.root.appendingPathComponent("export.json")
    let document = try SettingsBackupDocument(configuration: current)
    try await service.export(document, to: destination)
    let first = try Data(contentsOf: destination)
    await #expect(throws: SettingsBackupError.self) { try await service.export(document, to: destination) }
    #expect(try Data(contentsOf: destination) == first)
}
@Test func settingsBackupRejectsInjectedMachineLocalRecordsAndInvalidProfileAssignments() async throws {
    let f = BackupFixture(); defer { f.cleanup() }
    let current = NativeConfiguration()
    let service = try f.prepare(current: current, imported: current)
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.source)) as? [String: Any])
    var config = try #require(object["configuration"] as? [String: Any])
    config["customRobloxPath"] = "/another/Roblox.app"
    object["configuration"] = config
    try JSONSerialization.data(withJSONObject: object).write(to: f.source)
    await #expect(throws: SettingsBackupError.self) { try await service.prepare(from: f.source, current: current) }
    var invalid = current
    invalid.shortcuts = [try GameShortcut(name: "Bad reference", placeID: "123")]
    invalid.shortcuts[0].engineProfileID = UUID()
    #expect(throws: (any Error).self) { try SettingsBackupDocument(configuration: invalid) }
}

@Test func settingsRestoreWorksBeforeTheFirstSettingsSaveAndKeepsGeneratedProfileIDs() async throws {
    let f = BackupFixture(); defer { f.cleanup() }
    try FileManager.default.createDirectory(at: f.root, withIntermediateDirectories: true)
    let current = NativeConfiguration()
    var imported = NativeConfiguration()
    imported.appearance.reduceMotion = true
    try SettingsBackupDocument(configuration: imported).data.write(to: f.source)
    let service = SettingsBackupService(directory: f.data)
    let plan = try await service.prepare(from: f.source, current: current)
    let recovery = try await service.restore(plan, current: current)
    #expect(try JSONDecoder().decode(NativeConfiguration.self, from: Data(contentsOf: recovery)) == current)
    #expect(try ConfigurationStore(directory: f.data).load().appearance.reduceMotion)
}

@Test func settingsRestoreAcceptsMigratedFilesWithGeneratedDefaultProfileIDs() async throws {
    let f = BackupFixture(); defer { f.cleanup() }
    try FileManager.default.createDirectory(at: f.data, withIntermediateDirectories: true)
    let old = Data(#"{"version":1,"shortcuts":[]}"#.utf8)
    try old.write(to: ConfigurationStore(directory: f.data).fileURL)
    let current = try ConfigurationStore(directory: f.data).load()
    try SettingsBackupDocument(configuration: current).data.write(to: f.source)
    let service = SettingsBackupService(directory: f.data)
    let plan = try await service.prepare(from: f.source, current: current)
    let recovery = try await service.restore(plan, current: current)
    #expect(try Data(contentsOf: recovery) == old)
    #expect(try ConfigurationStore(directory: f.data).load().engine == current.engine)
}
