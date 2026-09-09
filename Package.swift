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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "ResetCore"),
        .executableTarget(
            name: "ResetApp",
            dependencies: [
                "ResetCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(name: "ResetCoreTests", dependencies: ["ResetCore"]),
    ],
    swiftLanguageModes: [.v5]
)
