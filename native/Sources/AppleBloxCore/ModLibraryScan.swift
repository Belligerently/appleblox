import Foundation

public struct ModLibraryIssue: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let message: String
}

public struct ModLibraryConflict: Equatable, Sendable {
    public let path: String
    public let modIDs: [UUID]
    public let names: [String]
}

public struct ModLibraryScan: Equatable, Sendable {
    public let mods: [ContentMod]
    public let issues: [ModLibraryIssue]
    /// Potential overlaps include disabled packs so toggling a pack updates findings immediately.
    public let overlaps: [ModLibraryConflict]

    public func activeConflicts(in current: [ContentMod]) -> [ModLibraryConflict] {
        let enabled = Set(current.filter(\.enabled).map(\.id))
        return overlaps.compactMap { overlap in
            let included = overlap.modIDs.indices.filter { enabled.contains(overlap.modIDs[$0]) }
            guard included.count > 1 else { return nil }
            return ModLibraryConflict(path: overlap.path, modIDs: included.map { overlap.modIDs[$0] }, names: included.map { overlap.names[$0] })
        }
    }

    public func blocksApplying(_ current: [ContentMod]) -> Bool {
        let enabled = Set(current.filter(\.enabled).map(\.id))
        return issues.contains { enabled.contains($0.id) } || !activeConflicts(in: current).isEmpty
    }

    public func summary(for current: [ContentMod]) -> String {
        let conflicts = activeConflicts(in: current).count
        return "Scanned \(mods.count) \(mods.count == 1 ? "pack" : "packs") · \(issues.count) \(issues.count == 1 ? "issue" : "issues") · \(conflicts) enabled \(conflicts == 1 ? "conflict" : "conflicts"). Rescan after edits; Apply Mods updates Player."
    }
}
