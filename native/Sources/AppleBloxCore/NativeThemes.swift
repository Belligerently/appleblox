import Foundation
import Darwin

public struct NativeThemeDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var name = "Custom Theme"
    public var accent = "#B12646"
    public var lightBackground = "#E6E6E6"
    public var darkBackground = "#171717"
    public var lightCard = "#F0F0F0"
    public var darkCard = "#1E1E1E"
    public init() {}
    public func validated() throws -> Self {
        guard version == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, name.utf8.count <= 320,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw NativeThemeError.invalid }
        for hex in [accent, lightBackground, darkBackground, lightCard, darkCard] {
            guard hex.count == 7, hex.first == "#" else { throw NativeThemeError.invalid }
            _ = try IconColor(hex: hex)
        }
        guard try Self.contrast(accent, "#FFFFFF") >= 3,
              try Self.contrast(lightBackground, "#171717") >= 4.5,
              try Self.contrast(lightCard, "#171717") >= 4.5,
              try Self.contrast(darkBackground, "#E4E5E8") >= 4.5,
              try Self.contrast(darkCard, "#E4E5E8") >= 4.5 else { throw NativeThemeError.contrast }
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
    public static func contrast(_ lhs: String, _ rhs: String) throws -> Double {
        func luminance(_ hex: String) throws -> Double {
            let c = try IconColor(hex: hex)
            let channels = [c.red, c.green, c.blue].map { value -> Double in
                let v = Double(value) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let a = try luminance(lhs), b = try luminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    public var json: Data { get throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(validated())
    } }
}
public enum NativeThemeError: LocalizedError {
    case invalid, contrast, full, missing
    public var errorDescription: String? {
        switch self {
        case .invalid: "Use a version 1 native theme, a name up to 80 characters, and six-digit #RRGGBB colors. CSS and bootstrapper XML are not supported."
        case .contrast: "Choose darker accent colors and readable light/dark surfaces. Accent needs 3:1 contrast with white; surfaces need 4.5:1 with their text."
        case .full: "The library holds up to 50 themes. Remove one before adding another."
        case .missing: "This theme is missing or unsafe. Existing files were preserved."
        }
    }
}
public struct NativeThemeRecord: Identifiable, Sendable {
    public let id: UUID
    public let theme: NativeThemeDocument
    public init(id: UUID, theme: NativeThemeDocument) { self.id = id; self.theme = theme }
}

public actor NativeThemeStore {
    private let directory: URL
    public init(dataDirectory: URL) { directory = SupportFiles.canonicalBase(dataDirectory).appendingPathComponent("native-themes", isDirectory: true) }
    public func folder() throws -> URL { try SupportFiles.prepareDirectory(directory); return directory }
    private func files() throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: folder(), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        guard files.count <= 50 else { throw NativeThemeError.full }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    public func read(_ id: UUID) throws -> NativeThemeDocument {
        let file = try folder().appendingPathComponent("\(id.uuidString).json")
        guard let bytes = try SupportFiles.readRegular(file, limit: 32_768) else { throw NativeThemeError.missing }
        return try Self.decode(bytes)
    }
    public static func decode(_ bytes: Data) throws -> NativeThemeDocument {
        guard bytes.count <= 32_768,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == ["version", "name", "accent", "lightBackground", "darkBackground", "lightCard", "darkCard"] else { throw NativeThemeError.invalid }
        return try JSONDecoder().decode(NativeThemeDocument.self, from: bytes).validated()
    }
    public func list() throws -> (records: [NativeThemeRecord], skipped: Int) {
        var records: [NativeThemeRecord] = []; var skipped = 0
        for file in try files() {
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)!
            do { records.append(NativeThemeRecord(id: id, theme: try read(id))) }
            catch { skipped += 1 }
        }
        return (records, skipped)
    }
    @discardableResult public func save(_ theme: NativeThemeDocument, id: UUID? = nil) throws -> UUID {
        let bytes = try theme.json
        if let id { _ = try read(id) }
        else { guard try files().count < 50 else { throw NativeThemeError.full } }
        let id = id ?? UUID()
        let file = try folder().appendingPathComponent("\(id.uuidString).json")
        let original = try SupportFiles.readRegular(file, limit: 32_768)
        let stage = directory.appendingPathComponent(".theme-\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: stage) }
        try SupportFiles.writePrivate(bytes, to: stage)
        guard try SupportFiles.readRegular(file, limit: 32_768) == original else { throw NativeThemeError.missing }
        if original == nil { try FileManager.default.linkItem(at: stage, to: file) }
        else if Darwin.rename(stage.path, file.path) != 0 { throw NativeThemeError.missing }
        return id
    }
    public func importFile(_ source: URL) throws {
        guard source.isFileURL, source.pathExtension.lowercased() == "json",
              let bytes = try SupportFiles.readRegular(source, limit: 32_768) else { throw NativeThemeError.invalid }
        try save(Self.decode(bytes))
    }
    public func remove(_ id: UUID) throws {
        _ = try read(id)
        let removed = try folder().appendingPathComponent("removed", isDirectory: true)
        try SupportFiles.prepareDirectory(removed)
        try FileManager.default.moveItem(at: directory.appendingPathComponent("\(id.uuidString).json"),
                                        to: removed.appendingPathComponent("\(UUID()).json"))
    }
    public func file(_ id: UUID) throws -> URL { _ = try read(id); return directory.appendingPathComponent("\(id.uuidString).json") }
}
