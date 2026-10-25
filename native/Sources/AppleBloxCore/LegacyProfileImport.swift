import Foundation

public enum LegacyProfileKind: String, Decodable, Sendable { case `default`, game }

public struct LegacyEngineProfile: Decodable, Sendable {
    private struct Row: Decodable, Sendable { let flag: String; let enabled: Bool; let value: FlagValue? }
    public let name: String
    public let type: LegacyProfileKind
    public let games: [String]?
    private let flags: [Row]
    private enum CodingKeys: String, CodingKey { case name, type, games, flags }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        games = try values.decodeIfPresent([String].self, forKey: .games)
        type = try values.decodeIfPresent(LegacyProfileKind.self, forKey: .type) ?? (games?.isEmpty == false ? .game : .default)
        flags = try values.decode([Row].self, forKey: .flags)
    }

    public func nativeProfile() throws -> EngineProfile { try converted().profile }
    public func converted() throws -> LegacyProfileConversion {
        guard flags.count <= 1000, Set(flags.map(\.flag)).count == flags.count else { throw FeatureError.message("Legacy profile contains too many or duplicate flag rows.") }
        guard flags.allSatisfy({ !$0.flag.isEmpty && $0.flag.utf8.count <= 256 }) else { throw FeatureError.message("Invalid legacy flag name.") }
        var profile = try EngineProfile(name: name).validated()
        profile.includesSelectedProfile = type == .game
        var warnings: [String] = []
        for row in flags {
            guard FastFlags.allowed.contains(row.flag), let value = row.value else {
                if row.enabled {
                    if !FastFlags.allowed.contains(row.flag) { throw EngineError.unsupportedFlags([row.flag]) }
                    throw EngineError.invalidValue(row.flag)
                }
                warnings.append("Skipped disabled flag \(row.flag) (unsupported or empty) in \(name).")
                continue
            }
            let normalized: FlagValue
            do { let values = try FastFlags.validate([row.flag: value])
                guard let valid = values[row.flag] else { throw EngineError.invalidValue(row.flag) }
                normalized = valid }
            catch {
                if row.enabled { throw error }
                warnings.append("Skipped disabled flag \(row.flag) (invalid value) in \(name).")
                continue
            }
            if row.enabled { profile.customFlags[row.flag] = normalized }
            else { profile.disabledCustomFlags[row.flag] = normalized }
        }
        var placeIDs: [String] = []
        if type == .game {
            guard let games, !games.isEmpty, games.count <= 200 else { throw FeatureError.message("A game profile needs 1–200 numeric place IDs.") }
            placeIDs = try games.map { try GameShortcut(name: name, placeID: $0).placeID }
            guard Set(placeIDs).count == placeIDs.count else { throw FeatureError.message("A game profile contains duplicate place IDs.") }
        } else if games?.isEmpty == false {
            warnings.append("Ignored game assignments on the global profile \(name).")
        }
        return LegacyProfileConversion(profile: try profile.validated(), kind: type, placeIDs: placeIDs, warnings: warnings)
    }
}

public struct LegacyProfileConversion: Sendable {
    public let profile: EngineProfile
    public let kind: LegacyProfileKind
    public let placeIDs: [String]
    public let warnings: [String]
}

public struct LegacyProfileImportPlan: Identifiable, Sendable {
    public let id = UUID()
    public let conversions: [LegacyProfileConversion]
    public let updatedAssignments: Int
    public let addedGames: Int
    public var warnings: [String] { conversions.flatMap(\.warnings) }
    private let original: NativeConfiguration
    private let result: NativeConfiguration

    public init(files: [Data], configuration: NativeConfiguration) throws {
        guard !files.isEmpty, files.count <= 50, files.allSatisfy({ $0.count <= 1_048_576 }),
              files.reduce(0, { $0 + $1.count }) <= 8_388_608 else { throw EngineError.fileTooLarge }
        let converted = try files.map { try JSONDecoder().decode(LegacyEngineProfile.self, from: $0).converted() }
        var next = configuration
        var seen: Set<String> = []
        var updated = 0, added = 0
        for conversion in converted {
            next.engine.profiles.append(conversion.profile)
            for placeID in conversion.placeIDs {
                guard seen.insert(placeID).inserted else { throw FeatureError.message("Multiple imported profiles target the same game. Import them separately to choose its assignment.") }
                if let index = next.shortcuts.firstIndex(where: { $0.placeID == placeID }) {
                    next.shortcuts[index].engineProfileID = conversion.profile.id
                    updated += 1
                } else {
                    var shortcut = try GameShortcut(name: conversion.profile.name, placeID: placeID)
                    shortcut.engineProfileID = conversion.profile.id
                    next.shortcuts.append(shortcut)
                    added += 1
                }
            }
        }
        conversions = converted; updatedAssignments = updated; addedGames = added
        original = configuration; result = try next.validated()
    }
    public func applying(to configuration: NativeConfiguration) throws -> NativeConfiguration {
        guard configuration == original else { throw FeatureError.message("Settings changed while the import review was open. Choose the files again.") }
        return result
    }
}
