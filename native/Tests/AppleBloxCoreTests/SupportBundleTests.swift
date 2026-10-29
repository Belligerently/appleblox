import Foundation
import Testing
@testable import AppleBloxCore

private func supportRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("ABSupport-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func supportDraft(logs: [LauncherLogEntry]? = nil) throws -> SupportBundleDraft {
    try SupportBundleDraft(report: DiagnosticsReport(), settings: SupportSettingsSummary(configuration: NativeConfiguration()), logs: logs)
}
private func unzip(_ arguments: [String]) throws -> Data {
    let process = Process(); let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = arguments; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return data
}

@Test func launcherLogsRotatePersistAndStayBounded() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = LauncherLogStore(dataDirectory: root, segmentBytes: 512, segmentCount: 2)
    for index in 0..<40 { try await store.append(.playerCountChanged, count: index, date: Date(timeIntervalSince1970: 1000 + Double(index))) }
    let entries = try await store.snapshot()
    #expect(entries.count < 40 && !entries.isEmpty)
    #expect(entries.last?.sequence == 40)
    #expect(entries.last?.count == 39)
    let reloaded = LauncherLogStore(dataDirectory: root, segmentBytes: 512, segmentCount: 2)
    #expect(try await reloaded.snapshot() == entries)
    try await reloaded.append(.appStarted)
    #expect(try await reloaded.snapshot().last?.sequence == 41)
    let file = root.appendingPathComponent("logs/launcher-log.json")
    #expect(try Data(contentsOf: file).count <= 512 * 2 + 4096)
    let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["launcher-log.json"])
}

@Test func launcherLogsClampCountsAndExcludeErrorUserInfo() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = LauncherLogStore(dataDirectory: root)
    let error = NSError(domain: "private-domain", code: 7, userInfo: [NSLocalizedDescriptionKey: "SECRET-cookie-name-/Users/private"])
    try await store.append(.operationFailed, count: Int.max, failure: SafeLogFailure(error))
    try await store.append(.playerCountChanged, count: -1)
    let entries = try await store.snapshot()
    #expect(entries.first?.count == 10_000 && entries.last?.count == 0)
    #expect(entries.first?.failure?.category == .other && entries.first?.failure?.code == 7)
    let bytes = try Data(contentsOf: root.appendingPathComponent("logs/launcher-log.json"))
    let text = String(decoding: bytes, as: UTF8.self)
    #expect(!text.contains("private") && !text.contains("SECRET"))
}

@Test func corruptAndOversizedLogsArePreserved() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = LauncherLogStore(dataDirectory: root, segmentBytes: 512, segmentCount: 1)
    let directory = try await store.checkedDirectory()
    let file = directory.appendingPathComponent("launcher-log.json")
    for bytes in [Data("broken".utf8), Data(repeating: 0, count: 5000)] {
        try bytes.write(to: file)
        await #expect(throws: (any Error).self) { try await store.append(.appStarted) }
        await #expect(throws: (any Error).self) { try await store.snapshot() }
        #expect(try Data(contentsOf: file) == bytes)
    }
}

@Test func unknownLogFieldsAndInvalidSequenceAreRejected() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = LauncherLogStore(dataDirectory: root)
    try await store.append(.appStarted)
    let file = root.appendingPathComponent("logs/launcher-log.json")
    let original = try Data(contentsOf: file)
    for mutation in 0..<3 {
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        if mutation == 0 { object["secret"] = "preserve" }
        if mutation == 1 { object["nextSequence"] = 99 }
        if mutation == 2 {
            var segments = try #require(object["segments"] as? [[[String: Any]]])
            segments[0][0]["secret"] = "preserve"; object["segments"] = segments
        }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: file)
        await #expect(throws: (any Error).self) { try await store.append(.activity) }
        #expect(try Data(contentsOf: file) == bytes)
    }
}

@Test func linkedLogsAndDirectoriesAreRejectedWithoutTouchingTargets() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let outside = root.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("logs"), withDestinationURL: outside)
    let store = LauncherLogStore(dataDirectory: root)
    await #expect(throws: (any Error).self) { try await store.append(.appStarted) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    try FileManager.default.removeItem(at: root.appendingPathComponent("logs"))
    let directory = try await store.checkedDirectory()
    let target = outside.appendingPathComponent("preserve")
    let original = Data("preserve".utf8); try original.write(to: target)
    let log = directory.appendingPathComponent("launcher-log.json")
    try FileManager.default.createSymbolicLink(at: log, withDestinationURL: target)
    await #expect(throws: (any Error).self) { try await store.snapshot() }
    try FileManager.default.removeItem(at: log)
    try FileManager.default.linkItem(at: target, to: log)
    await #expect(throws: (any Error).self) { try await store.append(.appStarted) }
    #expect(try Data(contentsOf: target) == original)
}

@Test func logRotationPreservesUnrelatedFiles() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = LauncherLogStore(dataDirectory: root, segmentBytes: 512, segmentCount: 1)
    let directory = try await store.checkedDirectory()
    let unrelated = directory.appendingPathComponent("my-notes.txt")
    try Data("private notes".utf8).write(to: unrelated)
    for _ in 0..<20 { try await store.append(.activity) }
    #expect(try String(contentsOf: unrelated, encoding: .utf8) == "private notes")
    let draft = try supportDraft(logs: await store.snapshot())
    #expect(!draft.files(includeLogs: true).contains { $0.text.contains("private notes") })
}

@Test func bundleSettingsExcludeAllRecordIdentifiersAndPaths() throws {
    var config = NativeConfiguration()
    config.customRobloxPath = "/Users/SECRET/Roblox.app"
    config.shortcuts = [try GameShortcut(name: "SECRET-game", placeID: "123456789")]
    config.features.accounts = [RobloxAccount(id: 987654321, name: "SECRET-user", displayName: "SECRET-display")]
    config.features.discordClientID = "987654321"
    config.features.mods = [ContentMod(name: "SECRET-pack", fileCount: 3)]
    config.features.discordPresence = true; config.appearance.theme = .dark
    let draft = try SupportBundleDraft(report: DiagnosticsReport(), settings: SupportSettingsSummary(configuration: config), logs: [])
    let settings = try #require(draft.files(includeLogs: true).first { $0.name == "settings-summary.json" })
    #expect(!settings.text.contains("SECRET") && !settings.text.contains("123456789") && !settings.text.contains("987654321"))
    #expect(settings.text.contains("Dark") && settings.text.contains("\"discordPresence\" : true"))
}

@Test func bundleOmissionsAndSnapshotAreExplicit() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = LauncherLogStore(dataDirectory: root)
    try await store.append(.appStarted)
    let draft = try supportDraft(logs: await store.snapshot())
    let reviewed = draft.files(includeLogs: true)
    try await store.append(.sessionJoined)
    #expect(draft.files(includeLogs: true) == reviewed)
    #expect(!draft.files(includeLogs: false).contains { $0.name == "launcher-events.jsonl" })
    let degraded = try SupportBundleDraft(report: DiagnosticsReport(), settings: nil, logs: nil)
    #expect(degraded.files(includeLogs: true).map(\.name) == ["README.txt", "diagnostics.txt"])
    #expect(degraded.files(includeLogs: true)[0].text.contains("omitted because settings were unreadable"))
    #expect(!degraded.hasLogs)
}

@Test func exportedZIPMatchesEveryReviewedByteAndHasPrivatePermissions() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = LauncherLogStore(dataDirectory: root); try await store.append(.appStarted)
    let draft = try supportDraft(logs: await store.snapshot())
    let exporter = SupportBundleExporter()
    for includeLogs in [true, false] {
        let file = root.appendingPathComponent("bundle-\(includeLogs).zip")
        try await exporter.save(draft, includeLogs: includeLogs, to: file)
        let names = String(decoding: try unzip(["-Z1", file.path]), as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(names == draft.files(includeLogs: includeLogs).map(\.name))
        for reviewed in draft.files(includeLogs: includeLogs) {
            #expect(try unzip(["-p", file.path, reviewed.name]) == Data(reviewed.text.utf8))
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".appleblox-support") }.isEmpty)
}

@Test func exportFailureCleansStageAndExistingExportsArePreserved() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let draft = try supportDraft()
    let destination = root.appendingPathComponent("support.zip")
    let failed = SupportBundleExporter(archiver: { _, _, _ in throw SupportFileError.archiveFailed })
    await #expect(throws: (any Error).self) { try await failed.save(draft, includeLogs: true, to: destination) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    let original = Data("existing".utf8); try original.write(to: destination)
    await #expect(throws: (any Error).self) { try await SupportBundleExporter().save(draft, includeLogs: true, to: destination) }
    #expect(try Data(contentsOf: destination) == original)
}

@Test func exportRefusesSymlinkAndConcurrentDestinationWithoutReplacingIt() async throws {
    let root = try supportRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let draft = try supportDraft()
    let target = root.appendingPathComponent("target.zip")
    let destination = root.appendingPathComponent("support.zip")
    try Data("original".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
    await #expect(throws: (any Error).self) { try await SupportBundleExporter().save(draft, includeLogs: true, to: destination) }
    #expect(try String(contentsOf: target, encoding: .utf8) == "original")
    try FileManager.default.removeItem(at: destination)
    let exporter = SupportBundleExporter(archiver: { directory, archive, names in
        try SupportBundleExporter.zip(directory: directory, archive: archive, names: names)
        try Data("created while archiving".utf8).write(to: destination)
    })
    await #expect(throws: (any Error).self) { try await exporter.save(draft, includeLogs: true, to: destination) }
    #expect(try String(contentsOf: destination, encoding: .utf8) == "created while archiving")
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".appleblox-support") }.isEmpty)
}
