// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleBloxNative",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AppleBloxNative", targets: ["AppleBloxNative"])],
    targets: [
        .target(name: "AppleBloxCore"),
        .executableTarget(name: "AppleBloxNative", dependencies: ["AppleBloxCore"]),
        .testTarget(name: "AppleBloxCoreTests", dependencies: ["AppleBloxCore"])
    ],
    swiftLanguageModes: [.v6]
)
