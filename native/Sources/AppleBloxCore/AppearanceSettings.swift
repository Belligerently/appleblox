import Foundation

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "System", light = "Light", dark = "Dark"
    public var id: Self { self }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var customTheme: NativeThemeDocument?
    public var customThemeID: UUID?
    public var theme: AppTheme = .system
    public var reduceMotion = false
    public var reduceTransparency = false
    public var showGameArtwork = true
    public init() {}

    private enum CodingKeys: String, CodingKey { case customTheme, customThemeID, theme, reduceMotion, reduceTransparency, showGameArtwork }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        customTheme = try values.decodeIfPresent(NativeThemeDocument.self, forKey: .customTheme)?.validated()
        customThemeID = try values.decodeIfPresent(UUID.self, forKey: .customThemeID)
        theme = try values.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        reduceMotion = try values.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        reduceTransparency = try values.decodeIfPresent(Bool.self, forKey: .reduceTransparency) ?? false
        showGameArtwork = try values.decodeIfPresent(Bool.self, forKey: .showGameArtwork) ?? true
    }
}
