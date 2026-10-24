import CoreGraphics

enum ForkLogoGeometry {
    static let width: CGFloat = 408
    static let height: CGFloat = 434

    static func outline() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 205.339, y: 87.3329))
        path.addLine(to: CGPoint(x: 206.841, y: 79.7727))
        path.addCurve(to: CGPoint(x: 213.35, y: 58.6772), control1: CGPoint(x: 208.314, y: 72.3542), control2: CGPoint(x: 210.516, y: 65.3105))
        path.addLine(to: CGPoint(x: 150.878, y: 41.9541))
        path.addLine(to: CGPoint(x: 88.4064, y: 25.2311))
        path.addLine(to: CGPoint(x: 4, y: 340.825))
        path.addLine(to: CGPoint(x: 319.594, y: 425.306))
        path.addLine(to: CGPoint(x: 344.008, y: 334.023))
        path.addCurve(to: CGPoint(x: 315.071, y: 287.611), control1: CGPoint(x: 326.869, y: 325.613), control2: CGPoint(x: 315.071, y: 307.99))
        path.addCurve(to: CGPoint(x: 334.095, y: 247.561), control1: CGPoint(x: 315.071, y: 271.457), control2: CGPoint(x: 322.484, y: 257.035))
        path.addCurve(to: CGPoint(x: 300.222, y: 199.04), control1: CGPoint(x: 314.327, y: 240.309), control2: CGPoint(x: 300.222, y: 221.321))
        path.addCurve(to: CGPoint(x: 351.889, y: 147.373), control1: CGPoint(x: 300.222, y: 170.505), control2: CGPoint(x: 323.354, y: 147.373))
        path.addCurve(to: CGPoint(x: 389.565, y: 163.685), control1: CGPoint(x: 366.747, y: 147.373), control2: CGPoint(x: 380.139, y: 153.644))
        path.addLine(to: CGPoint(x: 404, y: 109.712))
        path.addLine(to: CGPoint(x: 340.615, y: 92.7445))
        path.addLine(to: CGPoint(x: 292.015, y: 79.7349))
        path.addCurve(to: CGPoint(x: 290.085, y: 80.8213), control1: CGPoint(x: 291.373, y: 80.1036), control2: CGPoint(x: 290.73, y: 80.4658))
        path.addCurve(to: CGPoint(x: 249.153, y: 94.7087), control1: CGPoint(x: 276.732, y: 88.1849), control2: CGPoint(x: 262.491, y: 92.9015))
        path.addCurve(to: CGPoint(x: 212.319, y: 90.602), control1: CGPoint(x: 235.963, y: 96.4959), control2: CGPoint(x: 222.855, y: 95.536))
        path.addLine(to: CGPoint(x: 205.339, y: 87.3329))
        path.closeSubpath()
        path.move(to: CGPoint(x: 259.824, y: 193.746))
        path.addLine(to: CGPoint(x: 171.771, y: 170.151))
        path.addLine(to: CGPoint(x: 148.101, y: 258.205))
        path.addLine(to: CGPoint(x: 236.229, y: 281.8))
        path.addLine(to: CGPoint(x: 259.824, y: 193.746))
        path.closeSubpath()
        path.move(to: CGPoint(x: 241.276, y: 33.9568))
        path.addCurve(to: CGPoint(x: 216.493, y: 81.6897), control1: CGPoint(x: 229.107, y: 46.8009), control2: CGPoint(x: 220.213, y: 62.9628))
        path.addCurve(to: CGPoint(x: 313.206, y: 50.5715), control1: CGPoint(x: 239.733, y: 92.5735), control2: CGPoint(x: 285.015, y: 81.0234))
        path.addCurve(to: CGPoint(x: 337.587, y: 1.57772), control1: CGPoint(x: 325.454, y: 37.6417), control2: CGPoint(x: 334.615, y: 21.2171))
        path.addCurve(to: CGPoint(x: 241.276, y: 33.9568), control1: CGPoint(x: 302.343, y: -4.69722), control2: CGPoint(x: 265.229, y: 8.07947))
        path.closeSubpath()
        return path
    }

    static func branchLines() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -14, y: 24))
        path.addLine(to: CGPoint(x: -14, y: -24))
        path.move(to: CGPoint(x: -14, y: 5))
        path.addCurve(to: CGPoint(x: 15, y: -13), control1: CGPoint(x: 15, y: 5), control2: CGPoint(x: 15, y: 5))
        path.addLine(to: CGPoint(x: 15, y: -24))
        var transform = CGAffineTransform(translationX: 204, y: 226).rotated(by: .pi / 12)
        return path.copy(using: &transform)!
    }

    static func branchNodes() -> CGPath {
        let path = CGMutablePath()
        for center in [CGPoint(x: -14, y: -24), CGPoint(x: 15, y: -24), CGPoint(x: -14, y: 24)] {
            path.addEllipse(in: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
        }
        var transform = CGAffineTransform(translationX: 204, y: 226).rotated(by: .pi / 12)
        return path.copy(using: &transform)!
    }
}
