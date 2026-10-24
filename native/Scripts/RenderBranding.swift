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
            // Match the system icon's 80% tile footprint within the icon canvas.
            let inset = size.width * 0.10
            let rect = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            let shape = CGPath(roundedRect: rect, cornerWidth: size.width * 0.18, cornerHeight: size.height * 0.18, transform: nil)
            context.saveGState()
            context.addPath(shape)
            context.clip()
            // Sampled from the Claude dark icon: charcoal at the top, near-black below.
            // Use RGB components to avoid grayscale-to-RGB gamma conversion.
            let top = CGColor(colorSpace: space, components: [44 / 255, 44 / 255, 44 / 255, 1])!
            let bottom = CGColor(colorSpace: space, components: [17 / 255, 17 / 255, 17 / 255, 1])!
            let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: size.width / 2, y: inset), end: CGPoint(x: size.width / 2, y: size.height - inset), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
            context.addPath(shape)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
            context.setLineWidth(max(0.5, size.width / 512))
            context.strokePath()
        }
        let scale = min(size.width / 408, size.height / 434) * (tile ? 0.60 : 0.96)
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
        fill(ForkLogoGeometry.bodyPath(), rule: .evenOdd, paint: gradient,
             start: CGPoint(x: 88.1429, y: 27.5218), end: CGPoint(x: 4.19202, y: 341.617))
        let blue = CGGradient(colorsSpace: space,
                              colors: [CGColor(red: 88 / 255, green: 191 / 255, blue: 1, alpha: 1),
                                       CGColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)] as CFArray,
                              locations: [0, 1])!
        fill(ForkLogoGeometry.leafPath(), paint: blue,
             start: CGPoint(x: 337, y: 0), end: CGPoint(x: 216, y: 82))
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }
}
