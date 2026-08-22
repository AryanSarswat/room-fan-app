// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModernFormsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ModernFormsKit", targets: ["ModernFormsKit"]),
        .executable(name: "mfctl", targets: ["mfctl"]),
        .executable(name: "blescan", targets: ["blescan"]),
    ],
    targets: [
        .target(name: "ModernFormsKit"),
        .executableTarget(name: "mfctl", dependencies: ["ModernFormsKit"]),
        .executableTarget(name: "blescan"),
        .testTarget(name: "ModernFormsKitTests", dependencies: ["ModernFormsKit"]),
    ]
)
