import SwiftUI

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
