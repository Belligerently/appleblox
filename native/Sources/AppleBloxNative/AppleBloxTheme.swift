import SwiftUI
import AppleBloxCore

// Values from legacy/frontend/src/theme.css; HSL converted to sRGB without changing the palette.
enum AppleBloxTheme {
    static let primary = Color(red: 0.694164, green: 0.149036, blue: 0.274506)
    static let primaryTextDark = Color(red: 0.966100, green: 0.833900, blue: 0.864416)

    static func background(for scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.09 : 0.9)
    }

    static func card(for scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.1176 : 0.94)
    }

    static func foreground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.89, green: 0.896667, blue: 0.91) : Color(white: 0.09)
    }

    static func selectedText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? primaryTextDark : primary
    }
}

struct NativePalette {
    var document: NativeThemeDocument?
    var accent: Color { document.map { Self.color($0.accent) } ?? AppleBloxTheme.primary }
    func background(_ scheme: ColorScheme) -> Color { document.map { Self.color(scheme == .dark ? $0.darkBackground : $0.lightBackground) } ?? AppleBloxTheme.background(for: scheme) }
    func card(_ scheme: ColorScheme) -> Color { document.map { Self.color(scheme == .dark ? $0.darkCard : $0.lightCard) } ?? AppleBloxTheme.card(for: scheme) }
    func selectedText(_ scheme: ColorScheme) -> Color { document == nil ? AppleBloxTheme.selectedText(for: scheme) : (scheme == .dark ? .white : AppleBloxTheme.foreground(for: scheme)) }
    static func color(_ hex: String) -> Color {
        guard let c = try? IconColor(hex: hex) else { return AppleBloxTheme.primary }
        return Color(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
    }
}
extension EnvironmentValues { @Entry var nativePalette = NativePalette() }
