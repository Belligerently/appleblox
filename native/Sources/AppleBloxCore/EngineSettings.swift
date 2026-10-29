import Foundation

public enum GraphicsRenderer: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, metal, openGL, vulkan
    public var id: Self { self }
    public var title: String {
        switch self {
        case .automatic: "Roblox default"
        case .metal: "Metal"
        case .openGL: "OpenGL"
        case .vulkan: "Vulkan (experimental)"
        }
    }
}

/// CSG mesh detail thresholds, independent of streamed objects and the in-game distance slider.
public enum ObjectDetailDistance: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, near, medium, far, veryFar
    public var id: Self { self }
    public var studs: Int? {
        switch self { case .automatic: nil; case .near: 50; case .medium: 100; case .far: 250; case .veryFar: 1000 }
    }
    public var title: String { studs.map { "\($0) studs" } ?? "Roblox default" }
}

public enum FlagValue: Codable, Equatable, Sendable {
    case boolean(Bool), integer(Int), string(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

public enum FastFlags {
    // Ported from the original AppleBlox local-client allowlist, not the full internal flag list.
    public static let allowed: Set<String> = [
        "DFIntCSGLevelOfDetailSwitchingDistance", "DFIntCSGLevelOfDetailSwitchingDistanceL12",
        "DFIntCSGLevelOfDetailSwitchingDistanceL23", "DFIntCSGLevelOfDetailSwitchingDistanceL34",
        "FFlagHandleAltEnterFullscreenManually", "DFFlagTextureQualityOverrideEnabled",
        "DFIntTextureQualityOverride", "FIntDebugForceMSAASamples", "DFFlagDisableDPIScale",
        "FFlagDebugGraphicsPreferD3D11", "FFlagDebugSkyGray", "DFFlagDebugPauseVoxelizer",
        "DFIntDebugFRMQualityLevelOverride", "DFIntDebugDynamicRenderKiloPixels",
        "FIntFRMMaxGrassDistance", "FIntFRMMinGrassDistance", "FFlagDebugGraphicsPreferVulkan",
        "FFlagDebugGraphicsPreferOpenGL", "FFlagDebugGraphicsDisableMetal", "FFlagDebugGraphicsPreferMetal",
        "FIntGrassMovementReducedMotionFactor"
    ]

    public static func validate(_ flags: [String: FlagValue]) throws -> [String: FlagValue] {
        let unknown = Set(flags.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else { throw EngineError.unsupportedFlags(unknown) }
        var result: [String: FlagValue] = [:]
        for (key, value) in flags {
            if key.hasPrefix("FFlag") || key.hasPrefix("DFFlag") {
                switch value {
                case .boolean: result[key] = value
                case .string(let string) where ["true", "false"].contains(string.lowercased()):
                    result[key] = .boolean(string.lowercased() == "true")
                default: throw EngineError.invalidValue(key)
                }
            } else {
                let integer: Int
                switch value {
                case .integer(let number): integer = number
                case .string(let string):
                    guard let number = Int(string) else { throw EngineError.invalidValue(key) }
                    integer = number
                default: throw EngineError.invalidValue(key)
                }
                guard Int32(exactly: integer) != nil else { throw EngineError.invalidValue(key) }
                result[key] = .integer(integer)
            }
        }
        return result
    }

    public static func parse(_ json: String) throws -> [String: FlagValue] {
        guard json.utf8.count <= 1_048_576 else { throw EngineError.fileTooLarge }
        do { return try validate(JSONDecoder().decode([String: FlagValue].self, from: Data(json.utf8))) }
        catch let error as EngineError { throw error }
        catch { throw EngineError.invalidJSON }
    }

    public static func json(_ flags: [String: FlagValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(validate(flags)), as: UTF8.self)
    }
}

public struct EngineProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var includesSelectedProfile = false
    public var renderer: GraphicsRenderer = .automatic
    public var separateQualityAndDistance = false
    public var objectDetailDistance: ObjectDetailDistance = .automatic
    public var disableVoxelShadows = false
    public var graphicsQuality: Int?
    public var textureQuality: Int?
    public var fullResolution = false
    public var graySky = false
    public var customFlags: [String: FlagValue] = [:]
    public var disabledCustomFlags: [String: FlagValue] = [:]

    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }

    private enum CodingKeys: String, CodingKey {
        case id, name, includesSelectedProfile, renderer, separateQualityAndDistance, objectDetailDistance, disableVoxelShadows, graphicsQuality, textureQuality, fullResolution, graySky, customFlags, disabledCustomFlags
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id), name: try values.decode(String.self, forKey: .name))
        includesSelectedProfile = try values.decodeIfPresent(Bool.self, forKey: .includesSelectedProfile) ?? false
        renderer = try values.decodeIfPresent(GraphicsRenderer.self, forKey: .renderer) ?? .automatic
        graphicsQuality = try values.decodeIfPresent(Int.self, forKey: .graphicsQuality)
        // Existing explicit quality overrides keep their effect when older profiles migrate.
        separateQualityAndDistance = try values.decodeIfPresent(Bool.self, forKey: .separateQualityAndDistance) ?? (graphicsQuality != nil)
        objectDetailDistance = try values.decodeIfPresent(ObjectDetailDistance.self, forKey: .objectDetailDistance) ?? .automatic
        disableVoxelShadows = try values.decodeIfPresent(Bool.self, forKey: .disableVoxelShadows) ?? false
        textureQuality = try values.decodeIfPresent(Int.self, forKey: .textureQuality)
        fullResolution = try values.decodeIfPresent(Bool.self, forKey: .fullResolution) ?? false
        graySky = try values.decodeIfPresent(Bool.self, forKey: .graySky) ?? false
        customFlags = try values.decodeIfPresent([String: FlagValue].self, forKey: .customFlags) ?? [:]
        disabledCustomFlags = try values.decodeIfPresent([String: FlagValue].self, forKey: .disabledCustomFlags) ?? [:]
    }

    public func validated() throws -> EngineProfile {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, result.name.count <= 80 else { throw EngineError.invalidProfileName }
        if let graphicsQuality, !(1...21).contains(graphicsQuality) { throw EngineError.invalidValue("Graphics quality (1–21)") }
        if separateQualityAndDistance && graphicsQuality == nil { throw EngineError.invalidValue("Choose a graphics quality level") }
        if let textureQuality, !(0...3).contains(textureQuality) { throw EngineError.invalidValue("Texture quality (0–3)") }
        result.customFlags = try FastFlags.validate(customFlags)
        result.disabledCustomFlags = try FastFlags.validate(disabledCustomFlags)
        guard Set(customFlags.keys).isDisjoint(with: disabledCustomFlags.keys) else {
            throw EngineError.invalidValue("Duplicate enabled and disabled flag")
        }
        return result
    }

    public func resolvedFlags() throws -> [String: FlagValue] {
        let profile = try validated()
        var flags: [String: FlagValue] = [:]
        switch profile.renderer {
        case .automatic: break
        case .metal: flags["FFlagDebugGraphicsPreferMetal"] = .boolean(true)
        case .vulkan:
            flags["FFlagDebugGraphicsDisableMetal"] = .boolean(true)
            flags["FFlagDebugGraphicsPreferVulkan"] = .boolean(true)
        case .openGL:
            flags["FFlagDebugGraphicsDisableMetal"] = .boolean(true)
            flags["FFlagDebugGraphicsPreferOpenGL"] = .boolean(true)
        }
        if let distance = profile.objectDetailDistance.studs {
            for key in ["DFIntCSGLevelOfDetailSwitchingDistance", "DFIntCSGLevelOfDetailSwitchingDistanceL12",
                        "DFIntCSGLevelOfDetailSwitchingDistanceL23", "DFIntCSGLevelOfDetailSwitchingDistanceL34"] {
                flags[key] = .integer(distance)
            }
        }
        if profile.disableVoxelShadows { flags["DFFlagDebugPauseVoxelizer"] = .boolean(true) }
        if profile.separateQualityAndDistance, let value = profile.graphicsQuality { flags["DFIntDebugFRMQualityLevelOverride"] = .integer(value) }
        if let value = profile.textureQuality {
            flags["DFFlagTextureQualityOverrideEnabled"] = .boolean(true)
            flags["DFIntTextureQualityOverride"] = .integer(value)
        }
        if profile.fullResolution { flags["DFFlagDisableDPIScale"] = .boolean(true) }
        if profile.graySky { flags["FFlagDebugSkyGray"] = .boolean(true) }
        // The advanced editor takes precedence, as in the original AppleBlox.
        flags.merge(profile.customFlags) { _, custom in custom }
        return flags
    }
}

public struct EngineConfiguration: Codable, Equatable, Sendable {
    public var profiles: [EngineProfile]
    public var selectedProfileID: UUID
    public var applyOnLaunch = false

    public init() {
        let profile = EngineProfile(id: UUID(uuidString: "606B34BA-9AA4-41B9-A104-88558792A5C1")!, name: "Default")
        profiles = [profile]
        selectedProfileID = profile.id
    }

    public var selectedProfile: EngineProfile? { profiles.first { $0.id == selectedProfileID } }

    public func resolvedFlags(for profileID: UUID? = nil) throws -> [String: FlagValue] {
        guard let selectedProfile, let target = profiles.first(where: { $0.id == (profileID ?? selectedProfileID) }) else { throw EngineError.invalidProfiles }
        let own = try target.resolvedFlags()
        guard target.includesSelectedProfile, target.id != selectedProfileID else { return own }
        return try selectedProfile.resolvedFlags().merging(own) { _, game in game }
    }

    public func validated() throws -> EngineConfiguration {
        var result = self
        result.profiles = try profiles.map { try $0.validated() }
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count,
              selectedProfile != nil else { throw EngineError.invalidProfiles }
        return result
    }
}

public enum EngineError: LocalizedError {
    case unsupportedFlags([String]), invalidValue(String), invalidJSON, invalidProfileName, invalidProfiles
    case fileTooLarge, unsafePath, changedSettings, invalidBackup, noBackup

    public var errorDescription: String? {
        switch self {
        case .unsupportedFlags(let keys): "These flags aren’t in AppleBlox’s local-client allowlist: \(keys.joined(separator: ", "))."
        case .invalidValue(let key): "Invalid value for \(key). Flags need a Boolean or a 32-bit integer of the correct type."
        case .invalidJSON: "Enter a JSON object of flag names and Boolean or integer values. Quoted values such as \"True\" and \"3\" are also accepted."
        case .invalidProfileName: "Give the profile a name of 1–80 characters."
        case .invalidProfiles: "Engine profiles must have unique identifiers and a valid selection."
        case .fileTooLarge: "The settings file is larger than 1 MB."
        case .unsafePath: "The ClientSettings path contains a symbolic link or isn’t a regular file or folder."
        case .changedSettings: "ClientAppSettings.json changed outside this app. It was left untouched. Your original backup is in the native settings folder."
        case .invalidBackup: "The settings backup is unreadable or belongs to a different installation. It was preserved."
        case .noBackup: "There’s no engine-settings backup for this Roblox installation."
        }
    }
}
