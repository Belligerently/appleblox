import AppKit

@main
struct RenderBranding {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try render(size: CGSize(width: 1024, height: 1089), tile: false, to: output.appendingPathComponent("AppleBloxFork.png"))
        let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for multiplier in [1, 2] {
                let pixels = points * multiplier
                let suffix = multiplier == 2 ? "@2x" : ""
                try render(size: CGSize(width: pixels, height: pixels), tile: true,
                           to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
    }

    static func render(size: CGSize, tile: Bool, to url: URL) throws {
        let width = Int(size.width), height = Int(size.height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        if tile {
            // Match the inherited AppleBlox tile footprint and dark burgundy glass finish.
            let inset = size.width * 0.075
            let rect = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            let shape = CGPath(roundedRect: rect, cornerWidth: size.width * 0.18, cornerHeight: size.height * 0.18, transform: nil)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -5 * size.width / 1024),
                              blur: size.width * 0.014, color: CGColor(gray: 0, alpha: 0.55))
            context.addPath(shape)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()
            context.restoreGState()
            context.saveGState()
            context.addPath(shape)
            context.clip()
            // Original AppleBlox uses near-black burgundy glass with a bright beveled rim.
            let top = CGColor(colorSpace: space, components: [12 / 255, 0, 0, 1])!
            let bottom = CGColor(colorSpace: space, components: [48 / 255, 0, 0, 1])!
            let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: size.width / 2, y: inset), end: CGPoint(x: size.width / 2, y: size.height - inset), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
            // A soft inward bevel, rather than a hard outline, matches the original glass tile.
            glassEdge(context, path: shape, bounds: rect,
                      depth: size.width * 0.007, blur: size.width * 0.008,
                      highlight: CGColor(gray: 1, alpha: 0.72), shade: CGColor(gray: 0, alpha: 0.55))

        }
        let scale = min(size.width / 408, size.height / 434) * (tile ? 0.70 : 0.96)
        context.translateBy(x: (size.width - 408 * scale) / 2, y: (size.height - 434 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let gradient = CGGradient(colorsSpace: space,
                                  colors: [CGColor(red: 206 / 255, green: 13 / 255, blue: 62 / 255, alpha: 1),
                                           CGColor(red: 133 / 255, green: 8 / 255, blue: 40 / 255, alpha: 1)] as CFArray,
                                  locations: [0, 1])!
        func fill(_ path: CGPath, rule: CGPathFillRule = .winding, paint: CGGradient, start: CGPoint, end: CGPoint) {
            context.saveGState()
            context.addPath(path)
            context.clip(using: rule)
            context.drawLinearGradient(paint, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }
        if tile {
            // Lift both pieces off the backing tile; even-odd fill preserves the Roblox opening.
            context.saveGState()
            context.setShadow(offset: CGSize(width: 3, height: -9), blur: 13,
                              color: CGColor(red: 0.02, green: 0, blue: 0.01, alpha: 0.78))
            context.setFillColor(CGColor(red: 0.3, green: 0.015, blue: 0.06, alpha: 1))
            context.addPath(ForkLogoGeometry.bodyPath())
            context.drawPath(using: .eoFill)
            context.addPath(ForkLogoGeometry.leafPath())
            context.fillPath()
            context.restoreGState()
        }
        fill(ForkLogoGeometry.bodyPath(), rule: .evenOdd, paint: gradient,
             start: CGPoint(x: 88.1429, y: 27.5218), end: CGPoint(x: 4.19202, y: 341.617))
        let blue = CGGradient(colorsSpace: space,
                              colors: [CGColor(red: 88 / 255, green: 191 / 255, blue: 1, alpha: 1),
                                       CGColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)] as CFArray,
                              locations: [0, 1])!
        fill(ForkLogoGeometry.leafPath(), paint: blue,
             start: CGPoint(x: 337, y: 0), end: CGPoint(x: 216, y: 82))
        if tile {
            let body = ForkLogoGeometry.bodyPath()
            let leaf = ForkLogoGeometry.leafPath()
            glassEdge(context, path: body, rule: .evenOdd, bounds: body.boundingBoxOfPath,
                      depth: 5.4, blur: 4.8,
                      highlight: CGColor(red: 1, green: 0.55, blue: 0.67, alpha: 0.85),
                      shade: CGColor(red: 0.2, green: 0, blue: 0.045, alpha: 0.78))
            glassEdge(context, path: leaf, bounds: leaf.boundingBoxOfPath,
                      depth: 3.8, blur: 3.5,
                      highlight: CGColor(red: 0.79, green: 0.96, blue: 1, alpha: 0.9),
                      shade: CGColor(red: 0, green: 0.12, blue: 0.33, alpha: 0.65))
            // Broad specular falloff makes the face read as glass, not just a stroked silhouette.
            let sheen = CGGradient(colorsSpace: space,
                colors: [CGColor(gray: 1, alpha: 0.12), CGColor(gray: 1, alpha: 0.015),
                         CGColor(gray: 0, alpha: 0.12)] as CFArray, locations: [0, 0.42, 1])!
            fill(body, rule: .evenOdd, paint: sheen, start: CGPoint(x: 100, y: 35), end: CGPoint(x: 260, y: 420))
            fill(leaf, paint: sheen, start: CGPoint(x: 280, y: 0), end: CGPoint(x: 280, y: 90))
        }
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }
    /// Shadows from the inverse silhouette form directional highlights inside the molded edge.
    /// The same even-odd mask lights the outer contour, the bite and the square opening.
    static func glassEdge(_ context: CGContext, path: CGPath, rule: CGPathFillRule = .winding,
                          bounds: CGRect, depth: CGFloat, blur: CGFloat,
                          highlight: CGColor, shade: CGColor) {
        let inverse = CGMutablePath()
        inverse.addRect(bounds.insetBy(dx: -100, dy: -100))
        inverse.addPath(path)
        for (offset, color, blend) in [
            (CGSize(width: depth, height: -depth), highlight, CGBlendMode.screen),
            (CGSize(width: -depth, height: depth), shade, CGBlendMode.multiply)
        ] {
            context.saveGState()
            context.addPath(path)
            context.clip(using: rule)
            context.setBlendMode(blend)
            context.setShadow(offset: offset, blur: blur, color: color)
            context.addPath(inverse)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.drawPath(using: .eoFill)
            context.restoreGState()
        }
    }

}
