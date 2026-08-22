// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ModernFormsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ModernFormsKit", targets: ["ModernFormsKit"]),
        .executable(name: "mfctl", targets: ["mfctl"]),
    ],
    targets: [
        .target(name: "ModernFormsKit"),
        .executableTarget(name: "mfctl", dependencies: ["ModernFormsKit"]),
        .testTarget(name: "ModernFormsKitTests", dependencies: ["ModernFormsKit"]),
    ]
)
