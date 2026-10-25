import DisplayBridge
import Foundation
import Testing
@testable import AppleBloxCore

@MainActor private final class FakeDisplay: TemporaryDisplayDriver {
    var active = false
    var starts = 0, stops = 0
    var failStart = false, failStop = false, failAfterActivation = false
    func start() throws {
        starts += 1
        if failStart { throw FeatureError.message("Fixture start failed") }
        active = true
        if failAfterActivation { throw FeatureError.message("Fixture partial start failed") }
    }
    func stop() throws {
        stops += 1
        if failStop { throw FeatureError.message("Fixture restoration failed") }
        active = false
    }
}

@Test func instanceSnapshotsOnlyTreatLastExitAsPlayerClosed() {
    let none = PlayerInstances([]), one = PlayerInstances([123]), two = PlayerInstances([123, 456])
    #expect(none.count == 0 && !none.canTrackOneGame)
    #expect(one.canTrackOneGame && !two.canTrackOneGame)
    #expect(!one.lastPlayerClosed(comparedTo: two))
    #expect(none.lastPlayerClosed(comparedTo: one))
    #expect(!none.lastPlayerClosed(comparedTo: none))
    #expect(PlayerInstances([-1, 0, 123]).ids == [123])
}

@Test func newInstanceOutcomesDoNotMistakeReusedOrExitedProcessesForSuccess() {
    #expect(PlayerLaunchOutcome.evaluate(requestNew: true, before: [123], after: [123, 456], reportedPID: 456) == .newInstance)
    #expect(PlayerLaunchOutcome.evaluate(requestNew: true, before: [123], after: [456], reportedPID: 456) == .replacedExisting)
    #expect(PlayerLaunchOutcome.evaluate(requestNew: true, before: [123], after: [123], reportedPID: 123) == .reusedExisting)
    #expect(PlayerLaunchOutcome.evaluate(requestNew: true, before: [123], after: [123], reportedPID: 456) == .unconfirmed)
    #expect(PlayerLaunchOutcome.evaluate(requestNew: false, before: [123], after: [123], reportedPID: 123) == .opened)
    #expect(PlayerLaunchOutcome.evaluate(requestNew: false, before: [], after: [], reportedPID: 0) == .unconfirmed)
}

@MainActor @Test func fpsDefaultOffDoesNotTouchDisplayAndNeedsAFreshPlayer() throws {
    let driver = FakeDisplay()
    let owned = FPSWorkaroundSession(driver: driver)
    let started = try owned.prepare(enabled: false, players: PlayerInstances([]))
    #expect(!started && driver.starts == 0)
    #expect(throws: FeatureError.self) { try owned.prepare(enabled: true, players: PlayerInstances([123])) }
    #expect(driver.starts == 0)
    try owned.stop()
    #expect(driver.stops == 0)
}

@MainActor @Test func fpsStartsOnceAndStaysActiveUntilTheLastPlayerCloses() throws {
    let driver = FakeDisplay()
    let owned = FPSWorkaroundSession(driver: driver)
    let started = try owned.prepare(enabled: true, players: PlayerInstances([]))
    #expect(started && owned.active && driver.starts == 1)
    let repeated = try owned.prepare(enabled: true, players: PlayerInstances([123]))
    #expect(!repeated && driver.starts == 1)
    try owned.playersChanged(PlayerInstances([123, 456]))
    try owned.playersChanged(PlayerInstances([456]))
    #expect(driver.stops == 0)
    try owned.playersChanged(PlayerInstances([]))
    #expect(!owned.active && driver.stops == 1)
    try owned.stop()
    #expect(driver.stops == 1)
}

@MainActor @Test func fpsLaunchFailureRollsBackOnlyWhenNoPlayerRemained() throws {
    let driver = FakeDisplay()
    let session = FPSWorkaroundSession(driver: driver)
    _ = try session.prepare(enabled: true, players: PlayerInstances([]))
    try session.launchFailed(startedHere: true, players: PlayerInstances([123]))
    #expect(session.active)
    try session.launchFailed(startedHere: false, players: PlayerInstances([]))
    #expect(session.active)
    try session.launchFailed(startedHere: true, players: PlayerInstances([]))
    #expect(!session.active && driver.stops == 1)
}

@MainActor @Test func fpsFailedRestorationRetainsOwnershipForRetryAndQuitCleanup() throws {
    let driver = FakeDisplay()
    let session = FPSWorkaroundSession(driver: driver)
    _ = try session.prepare(enabled: true, players: PlayerInstances([]))
    driver.failStop = true
    #expect(throws: FeatureError.self) { try session.stop() }
    #expect(session.active)
    driver.failStop = false
    try session.stop()
    #expect(!session.active && driver.stops == 2)
    driver.failStart = true
    #expect(throws: FeatureError.self) { try session.prepare(enabled: true, players: PlayerInstances([])) }
    #expect(!session.active)
}

@MainActor @Test func nativeDisplayBridgeProbeAndInactiveStopAreInert() throws {
    let driver = ABTemporaryDisplay()
    _ = ABTemporaryDisplay.available // Introspection only; never calls begin or creates a display.
    #expect(!driver.isActive)
    try driver.stop()
    #expect(!driver.isActive)
}

@Test func fpsPreferenceMigratesOffAndRoundTripsWithoutAddingRejectedFlags() throws {
    var settings = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
    #expect(!settings.experimentalFPSWorkaround)
    settings.experimentalFPSWorkaround = true
    #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    #expect(!FastFlags.allowed.contains("DFIntTaskSchedulerTargetFps"))
    #expect(!FastFlags.allowed.contains("FFlagDisablePostFx"))
    #expect(!FastFlags.allowed.contains("DFFlagDebugRenderForceTechnologyVoxel"))
}

@Test func multiplePlayerDiscordPresenceNeverMixesSessionsOrSDKDetails() throws {
    let session = PlaySession(placeID: "1818", name: "Private game")
    var custom = BloxstrapPresenceState()
    custom.apply(try #require(BloxstrapPresencePatch.parse(#"[FLog::Output] [BloxstrapRPC] {"command":"SetRichPresence","data":{"details":"Private SDK detail"}}"#)))
    let activity = DiscordActivity(session: session, options: .init(showArtwork: true, allowGameControl: true), custom: custom, runningPlayers: 2)
    #expect(activity.details == "Multiple Roblox Players")
    #expect(activity.timestamps == nil && activity.assets == nil && activity.buttons == nil)
    let json = String(decoding: try JSONEncoder().encode(activity), as: UTF8.self)
    #expect(!json.contains("1818") && !json.contains("Private"))
}

@Test func switchingBackToExistingPlayerLogsDoesNotReplayOldJoinsOrLosePartialLines() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABInstanceLogs-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let first = root.appendingPathComponent("Player_first.log"), second = root.appendingPathComponent("Player_second.log")
    let old = "[FLog::Output] ! Joining game 'old' place 123 at 8.8.8.8\n"
    let new = "[FLog::Output] ! Joining game 'new' place 1818 at 8.8.8.8\n"
    try Data(old.utf8).write(to: first)
    try Data(old.utf8).write(to: second)
    let now = Date()
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: second.path)
    let reader = PlayerLogReader()
    #expect(try await reader.poll(directory: root, now: now).isEmpty)
    let firstHandle = try FileHandle(forWritingTo: first)
    defer { try? firstHandle.close() }
    try firstHandle.seekToEnd()
    try firstHandle.write(contentsOf: Data(new.utf8.dropLast()))
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(1)], ofItemAtPath: first.path)
    #expect(try await reader.poll(directory: root, now: now).isEmpty)
    let secondHandle = try FileHandle(forWritingTo: second)
    defer { try? secondHandle.close() }
    try secondHandle.seekToEnd()
    try secondHandle.write(contentsOf: Data(new.utf8))
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(2)], ofItemAtPath: second.path)
    #expect(try await reader.poll(directory: root, now: now) == [.joining("1818")])
    try firstHandle.write(contentsOf: Data("\n".utf8))
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(3)], ofItemAtPath: first.path)
    #expect(try await reader.poll(directory: root, now: now) == [.joining("1818")])
}

@Test func resetBaselinesAllFilesAndIgnoresSymlinkedLogs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ABLogBaseline-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let outside = root.appendingPathComponent("outside.txt"), link = root.appendingPathComponent("Player_link.log")
    try Data("[FLog::Output] ! Joining game 'old' place 123 at 8.8.8.8\n".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    let reader = PlayerLogReader()
    #expect(try await reader.poll(directory: root).isEmpty)
    #expect(try await reader.poll(directory: root).isEmpty)
    await reader.reset()
    #expect(try await reader.poll(directory: root).isEmpty)
}

@MainActor @Test func fpsPartialStartFailureRemainsOwnedUntilRollback() throws {
    let driver = FakeDisplay()
    driver.failAfterActivation = true
    let session = FPSWorkaroundSession(driver: driver)
    #expect(throws: FeatureError.self) { try session.prepare(enabled: true, players: PlayerInstances([])) }
    #expect(session.active)
    try session.launchFailed(startedHere: session.active, players: PlayerInstances([]))
    #expect(!session.active && driver.stops == 1)
}
