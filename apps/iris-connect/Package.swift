// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IrisConnect",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "IrisConnect", targets: ["IrisConnect"]), .executable(name: "IrisRead", targets: ["IrisRead"]), .executable(name: "IrisControl", targets: ["IrisControl"])],
    targets: [
        .target(name: "ConnectCore"),
        .executableTarget(name: "IrisConnect", dependencies: ["ConnectCore"]),
        .executableTarget(name: "IrisRead", dependencies: ["ConnectCore"]),
        .executableTarget(name: "IrisControl", dependencies: ["ConnectCore"]),
        .testTarget(name: "ConnectCoreTests", dependencies: ["ConnectCore"]),
        .testTarget(name: "NativeReadTests", dependencies: ["IrisConnect", "ConnectCore"])
    ],
    swiftLanguageModes: [.v5]
)
