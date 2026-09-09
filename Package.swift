// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ResetMe",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        // Keep the executable name stable: Info.plist and the app bundle use it.
        .executable(name: "reset", targets: ["ResetApp"]),
    ],
    targets: [
        .target(name: "ResetCore"),
        .executableTarget(name: "ResetApp", dependencies: ["ResetCore"]),
        .testTarget(name: "ResetCoreTests", dependencies: ["ResetCore"]),
    ],
    swiftLanguageModes: [.v5]
)
