import Foundation
import Testing
@testable import AppleBloxCore

private struct ResetFixture {
    let root: URL
    let data: URL
    let service: NativeResetService
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ABReset-\(UUID())")
        data = root.appendingPathComponent("Native Data")
        try ConfigurationStore(directory: data).save(NativeConfiguration())
        for folder in ["engine-backups", "mods", "logs", "launcher-icons", "native-themes"] {
            let dir = data.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("preserve-\(folder)".utf8).write(to: dir.appendingPathComponent("original.bin"))
        }
        service = NativeResetService(dataDirectory: data)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
private actor ResetCredentials {
    var cleared = false
    func clear(afterArchive archive: URL, old: URL) throws {
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: archive.appendingPathComponent("data/engine-backups/original.bin").path))
        cleared = true
    }
}
@Test func resetArchivesAllNativeFilesBeforeClearingCredentials() async throws {
    let f = try ResetFixture(); defer { f.cleanup() }
    let review = try await f.service.prepare(); let credentials = ResetCredentials()
    let result = try await f.service.commit(review) { try await credentials.clear(afterArchive: review.recoveryDirectory, old: f.data) }
    #expect(await credentials.cleared)
    #expect(result == review.recoveryDirectory)
    #expect(!FileManager.default.fileExists(atPath: f.data.path))
    for folder in ["engine-backups", "mods", "logs", "launcher-icons", "native-themes"] {
        #expect(try String(contentsOf: result.appendingPathComponent("data/\(folder)/original.bin"), encoding: .utf8) == "preserve-\(folder)")
    }
    #expect(FileManager.default.fileExists(atPath: result.appendingPathComponent("RECOVERY.txt").path))
    let attrs = try FileManager.default.attributesOfItem(atPath: result.path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}
@Test func failedCredentialCleanupRollsBackDataWithoutLosingBackups() async throws {
    let f = try ResetFixture(); defer { f.cleanup() }
    let original = try Data(contentsOf: f.data.appendingPathComponent("native-settings.json"))
    let review = try await f.service.prepare()
    await #expect(throws: (any Error).self) { try await f.service.commit(review) { throw NativeResetError.busy } }
    #expect(try Data(contentsOf: f.data.appendingPathComponent("native-settings.json")) == original)
    #expect(FileManager.default.fileExists(atPath: f.data.appendingPathComponent("engine-backups/original.bin").path))
    #expect(!FileManager.default.fileExists(atPath: review.recoveryDirectory.path))
}
@Test func resetRefusesStaleSettingsAndNewFilesWithoutCallingCredentialCleanup() async throws {
    let f = try ResetFixture(); defer { f.cleanup() }
    var review = try await f.service.prepare()
    var config = NativeConfiguration(); config.appearance.reduceMotion = true
    try ConfigurationStore(directory: f.data).save(config)
    await #expect(throws: (any Error).self) { try await f.service.commit(review) { Issue.record("Credentials cleared from stale review") } }
    review = try await f.service.prepare()
    try Data("[]".utf8).write(to: f.data.appendingPathComponent("play-history.json"))
    await #expect(throws: (any Error).self) { try await f.service.commit(review) { Issue.record("Credentials cleared after contents changed") } }
    #expect(FileManager.default.fileExists(atPath: f.data.path))
}
@Test func resetRejectsUnknownFilesLinkedRootsAndCorruptSettings() async throws {
    let f = try ResetFixture(); defer { f.cleanup() }
    let notes = f.data.appendingPathComponent("personal.txt"); try Data("preserve".utf8).write(to: notes)
    await #expect(throws: (any Error).self) { try await f.service.prepare() }
    try FileManager.default.removeItem(at: notes)
    let alias = f.root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.data)
    await #expect(throws: (any Error).self) { try await NativeResetService(dataDirectory: alias).prepare() }
    let file = f.data.appendingPathComponent("native-settings.json"); try Data("broken".utf8).write(to: file)
    await #expect(throws: (any Error).self) { try await f.service.prepare() }
    #expect(try String(contentsOf: file, encoding: .utf8) == "broken")
}
@Test func resetPreservesArchivesIfRollbackCannotReplaceAnExternalNewFolder() async throws {
    let f = try ResetFixture(); defer { f.cleanup() }
    let review = try await f.service.prepare()
    await #expect(throws: (any Error).self) {
        try await f.service.commit(review) {
            try FileManager.default.createDirectory(at: f.data, withIntermediateDirectories: false)
            try Data("external".utf8).write(to: f.data.appendingPathComponent("notes.txt"))
            throw NativeResetError.busy
        }
    }
    #expect(FileManager.default.fileExists(atPath: review.recoveryDirectory.appendingPathComponent("data/engine-backups/original.bin").path))
    #expect(try String(contentsOf: f.data.appendingPathComponent("notes.txt"), encoding: .utf8) == "external")
}
@Test func accountNamespacesKeepTheExistingDefaultAndIsolateOtherDataStores() {
    let standard = ConfigurationStore.defaultDirectory(environment: [:])
    #expect(AccountVault.service(for: standard) == "io.github.Belligerently.AppleBloxNative.sessions")
    let a = URL(fileURLWithPath: "/private/tmp/appleblox-reset-qa")
    let b = URL(fileURLWithPath: "/private/tmp/appleblox-theme-qa")
    #expect(AccountVault.service(for: a) != AccountVault.service(for: standard))
    #expect(AccountVault.service(for: a) != AccountVault.service(for: b))
    #expect(AccountVault.service(for: a) == AccountVault.service(for: a))
}
