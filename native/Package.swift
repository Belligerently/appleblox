// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleBloxNative",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AppleBloxNative", targets: ["AppleBloxNative"])],
    targets: [
        .target(name: "AppleBloxCore"),
        .target(name: "DisplayBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]),
        .executableTarget(name: "AppleBloxNative", dependencies: ["AppleBloxCore", "DisplayBridge"]),
        .testTarget(name: "AppleBloxCoreTests", dependencies: ["AppleBloxCore", "DisplayBridge"])
    ],
    swiftLanguageModes: [.v6]
)
