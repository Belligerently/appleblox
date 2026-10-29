import SwiftUI

struct AppleBloxForkLogo: View {
    private let gradient = LinearGradient(
        colors: [Color(red: 206 / 255, green: 13 / 255, blue: 62 / 255),
                 Color(red: 133 / 255, green: 8 / 255, blue: 40 / 255)],
        startPoint: UnitPoint(x: 88.1429 / 408, y: 27.5218 / 434),
        endPoint: UnitPoint(x: 4.19202 / 408, y: 341.617 / 434)
    )

    private let leafGradient = LinearGradient(
        colors: [Color(red: 88 / 255, green: 191 / 255, blue: 1),
                 Color(red: 10 / 255, green: 132 / 255, blue: 1)],
        startPoint: UnitPoint(x: 337.0 / 408, y: 0),
        endPoint: UnitPoint(x: 216.0 / 408, y: 82.0 / 434)
    )

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / ForkLogoGeometry.width, geometry.size.height / ForkLogoGeometry.height)
            let transform = CGAffineTransform(
                translationX: (geometry.size.width - ForkLogoGeometry.width * scale) / 2,
                y: (geometry.size.height - ForkLogoGeometry.height * scale) / 2
            ).scaledBy(x: scale, y: scale)
            ZStack {
                Path(ForkLogoGeometry.bodyPath()).applying(transform)
                    .fill(gradient, style: FillStyle(eoFill: true))
                Path(ForkLogoGeometry.leafPath()).applying(transform).fill(leafGradient)
            }
        }
        .accessibilityHidden(true)
    }
}
