import Foundation

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "System", light = "Light", dark = "Dark"
    public var id: Self { self }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var theme: AppTheme = .system
    public var reduceMotion = false
    public var reduceTransparency = false
    public var showGameArtwork = true
    public init() {}

    private enum CodingKeys: String, CodingKey { case theme, reduceMotion, reduceTransparency, showGameArtwork }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        reduceMotion = try values.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        reduceTransparency = try values.decodeIfPresent(Bool.self, forKey: .reduceTransparency) ?? false
        showGameArtwork = try values.decodeIfPresent(Bool.self, forKey: .showGameArtwork) ?? true
    }
}
