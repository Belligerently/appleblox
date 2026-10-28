import Foundation

public struct FlagEditorRow: Equatable, Identifiable, Sendable {
    public let id: UUID
    public private(set) var name: String
    public var value: String
    public var enabled: Bool
    public var isBoolean: Bool { name.hasPrefix("FFlag") || name.hasPrefix("DFFlag") }

    public init(name: String, value: FlagValue, enabled: Bool = true) {
        id = UUID()
        self.name = name
        switch value {
        case .boolean(let value): self.value = value ? "true" : "false"
        case .integer(let value): self.value = String(value)
        case .string(let value): self.value = value
        }
        self.enabled = enabled
    }

    fileprivate mutating func rename(to name: String) { self.name = name }

    public func validatedValue() throws -> FlagValue {
        let values = try FastFlags.validate([name: .string(value.trimmingCharacters(in: .whitespacesAndNewlines))])
        guard let value = values[name] else { throw EngineError.invalidValue(name) }
        return value
    }
}

/// A sheet's editable snapshot; incomplete edits never reach saved settings or Player.
public struct FlagEditorDraft: Equatable, Sendable {
    public var rows: [FlagEditorRow]

    public init(profile: EngineProfile) {
        rows = profile.customFlags.map { FlagEditorRow(name: $0.key, value: $0.value) }
        rows += profile.disabledCustomFlags.map { FlagEditorRow(name: $0.key, value: $0.value, enabled: false) }
        rows.sort { $0.name < $1.name }
    }

    public func matching(_ query: String) -> [FlagEditorRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
    }

    public mutating func add(_ name: String) throws {
        guard FastFlags.allowed.contains(name) else { throw EngineError.unsupportedFlags([name]) }
        guard !rows.contains(where: { $0.name == name }) else { throw EngineError.invalidValue("Duplicate flag: \(name)") }
        let boolean = name.hasPrefix("FFlag") || name.hasPrefix("DFFlag")
        rows.append(FlagEditorRow(name: name, value: boolean ? .boolean(false) : .integer(0)))
        rows.sort { $0.name < $1.name }
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { throw EngineError.invalidValue("Missing flag") }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FastFlags.allowed.contains(name) else { throw EngineError.unsupportedFlags([name]) }
        guard !rows.contains(where: { $0.id != id && $0.name == name }) else { throw EngineError.invalidValue("Duplicate flag: \(name)") }
        var renamed = rows[index]
        renamed.rename(to: name)
        _ = try renamed.validatedValue()
        rows[index] = renamed
        rows.sort { $0.name < $1.name }
    }

    public mutating func setEnabled(_ enabled: Bool, for ids: Set<UUID>) {
        for index in rows.indices where ids.contains(rows[index].id) { rows[index].enabled = enabled }
    }

    /// Explicit selection export includes disabled rows' values; it does not change their saved state.
    public func selectedJSON(_ ids: Set<UUID>) throws -> String {
        var values: [String: FlagValue] = [:]
        for row in rows where ids.contains(row.id) {
            guard values[row.name] == nil else { throw EngineError.invalidValue("Duplicate flag: \(row.name)") }
            values[row.name] = try row.validatedValue()
        }
        return try FastFlags.json(values)
    }

    public mutating func remove(_ ids: Set<UUID>) { rows.removeAll { ids.contains($0.id) } }

    /// JSON represents enabled custom overrides. Disabled rows remain unless JSON enables the same name.
    public mutating func replaceEnabledJSON(_ json: String) throws {
        let flags = try FastFlags.parse(json)
        guard Set(rows.map(\.name)).count == rows.count else { throw EngineError.invalidValue("Duplicate flag") }
        let existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0) })
        var next = rows.filter { !$0.enabled && flags[$0.name] == nil }
        for (name, value) in flags {
            var row = existing[name] ?? FlagEditorRow(name: name, value: value)
            row.value = FlagEditorRow(name: name, value: value).value
            row.enabled = true
            next.append(row)
        }
        rows = next.sorted { $0.name < $1.name }
    }

    public func enabledJSON() throws -> String {
        try FastFlags.json(values(enabled: true))
    }

    public func applying(to profile: EngineProfile) throws -> EngineProfile {
        guard Set(rows.map(\.name)).count == rows.count else { throw EngineError.invalidValue("Duplicate flag") }
        var result = profile
        result.customFlags = try values(enabled: true)
        result.disabledCustomFlags = try values(enabled: false)
        return try result.validated()
    }

    private func values(enabled: Bool) throws -> [String: FlagValue] {
        var result: [String: FlagValue] = [:]
        for row in rows where row.enabled == enabled {
            guard result[row.name] == nil else { throw EngineError.invalidValue("Duplicate flag: \(row.name)") }
            result[row.name] = try row.validatedValue()
        }
        return result
    }
}
