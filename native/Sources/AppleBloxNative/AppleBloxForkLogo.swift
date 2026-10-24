import SwiftUI

struct AppleBloxForkLogo: View {
    private let gradient = LinearGradient(
        colors: [Color(red: 206 / 255, green: 13 / 255, blue: 62 / 255),
                 Color(red: 133 / 255, green: 8 / 255, blue: 40 / 255)],
        startPoint: UnitPoint(x: 88.1429 / 408, y: 27.5218 / 434),
        endPoint: UnitPoint(x: 4.19202 / 408, y: 341.617 / 434)
    )

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / ForkLogoGeometry.width, geometry.size.height / ForkLogoGeometry.height)
            let transform = CGAffineTransform(
                translationX: (geometry.size.width - ForkLogoGeometry.width * scale) / 2,
                y: (geometry.size.height - ForkLogoGeometry.height * scale) / 2
            ).scaledBy(x: scale, y: scale)
            Path(ForkLogoGeometry.outline()).applying(transform)
                .fill(gradient, style: FillStyle(eoFill: true))
        }
        .accessibilityHidden(true)
    }
}
