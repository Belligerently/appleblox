import Foundation

public enum PlayerLaunchOutcome: Equatable, Sendable {
    case opened, newInstance, replacedExisting, reusedExisting, unconfirmed
    public static func evaluate(requestNew: Bool, before: Set<Int32>, after: Set<Int32>, reportedPID: Int32) -> Self {
        guard after.contains(reportedPID) else { return .unconfirmed }
        guard requestNew else { return .opened }
        if before.contains(reportedPID) { return .reusedExisting }
        if !before.isEmpty, before.isDisjoint(with: after) { return .replacedExisting }
        return .newInstance
    }
}

public struct PlayerInstances: Equatable, Sendable {
    public let ids: Set<Int32>
    public init(_ ids: Set<Int32>) { self.ids = ids.filter { $0 > 0 } }
    public var count: Int { ids.count }
    public var canTrackOneGame: Bool { count == 1 }
    public func lastPlayerClosed(comparedTo before: Self) -> Bool { !before.ids.isEmpty && ids.isEmpty }
}

@MainActor public protocol TemporaryDisplayDriver: AnyObject {
    var active: Bool { get }
    func start() throws
    func finishStart() throws -> Bool
    func stop() throws
}

public extension TemporaryDisplayDriver {
    func finishStart() throws -> Bool { true }
}

/// Coordinates main-thread display resources with Player lifetime; no display API is used in tests.
@MainActor public final class FPSWorkaroundSession {
    private let driver: any TemporaryDisplayDriver
    public init(driver: any TemporaryDisplayDriver) { self.driver = driver }
    public var active: Bool { driver.active }
    @discardableResult public func prepare(enabled: Bool, players: PlayerInstances) async throws -> Bool {
        guard enabled, !active else { return false }
        guard players.count == 0 else { throw FeatureError.message("Quit all Roblox Players before starting the FPS workaround.") }
        try Task.checkCancellation()
        try driver.start()
        guard active else { throw FeatureError.message("The temporary display did not become active.") }
        for _ in 0..<50 {
            try Task.checkCancellation()
            guard active else { throw FeatureError.message("The temporary display was stopped before it became ready.") }
            if try driver.finishStart() { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw FeatureError.message("macOS did not register the temporary display within five seconds.")
    }
    public func stop() throws { if active { try driver.stop() } }
    public func playersChanged(_ players: PlayerInstances) throws { if players.count == 0 { try stop() } }
    public func launchFailed(startedHere: Bool, players: PlayerInstances) throws {
        if startedHere, players.count == 0 { try stop() }
    }
}
