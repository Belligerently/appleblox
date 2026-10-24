import Foundation

public struct GameShortcut: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var placeID: String
    public var engineProfileID: UUID?

    public init(id: UUID = UUID(), name: String, placeID: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedID = placeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ConfigurationError.emptyName }
        guard !trimmedID.isEmpty, trimmedID.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = UInt64(trimmedID), number > 0 else {
            throw ConfigurationError.invalidPlaceID
        }
        self.id = id
        self.name = trimmedName
        self.placeID = String(number)
    }

    public var launchURL: URL {
        URL(string: "roblox://experiences/start?placeId=\(placeID)")!
    }

    public func validated() throws -> GameShortcut {
        var result = try GameShortcut(id: id, name: name, placeID: placeID)
        result.engineProfileID = engineProfileID
        return result
    }
}

public struct NativeConfiguration: Codable, Equatable, Sendable {
    public var version = 1
    public var customRobloxPath: String?
    public var shortcuts: [GameShortcut] = []
    public var engine = EngineConfiguration()
    public var features = FeatureSettings()
    public var appearance = AppearanceSettings()

    public init() {}

    private enum CodingKeys: String, CodingKey { case version, customRobloxPath, shortcuts, engine, features, appearance }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        customRobloxPath = try container.decodeIfPresent(String.self, forKey: .customRobloxPath)
        shortcuts = try container.decode([GameShortcut].self, forKey: .shortcuts)
        engine = try container.decodeIfPresent(EngineConfiguration.self, forKey: .engine) ?? EngineConfiguration()
        features = try container.decodeIfPresent(FeatureSettings.self, forKey: .features) ?? FeatureSettings()
        appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? AppearanceSettings()
    }

    public func validated() throws -> NativeConfiguration {
        guard version == 1 else { throw ConfigurationError.unsupportedVersion }
        var result = self
        result.engine = try engine.validated()
        result.features = try features.validated()
        result.shortcuts = try shortcuts.map { try $0.validated() }
        guard result.shortcuts.allSatisfy({ shortcut in
            shortcut.engineProfileID == nil || engine.profiles.contains(where: { $0.id == shortcut.engineProfileID })
        }) else {
            throw EngineError.invalidProfiles
        }
        guard Set(result.shortcuts.map(\.id)).count == result.shortcuts.count else {
            throw ConfigurationError.duplicateIDs
        }
        return result
    }
}

public enum ConfigurationError: LocalizedError {
    case emptyName, invalidPlaceID, unsupportedVersion, duplicateIDs

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Give the shortcut a name."
        case .invalidPlaceID: "Enter a positive numeric place ID from a Roblox game URL."
        case .unsupportedVersion: "This settings file was created by an unsupported app version."
        case .duplicateIDs: "The settings file contains duplicate shortcut identifiers."
        }
    }
}

public struct ConfigurationStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("native-settings.json") }

    public init(directory: URL) { self.directory = directory }

    public static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["APPLEBLOX_NATIVE_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AppleBlox Native", isDirectory: true)
    }

    public func load() throws -> NativeConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return NativeConfiguration() }
        return try JSONDecoder().decode(NativeConfiguration.self, from: Data(contentsOf: fileURL)).validated()
    }

    public func save(_ configuration: NativeConfiguration) throws {
        let validated = try configuration.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validated)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
