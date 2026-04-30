// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KadrCaptions",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "KadrCaptions", targets: ["KadrCaptions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SteliyanH/kadr.git", from: "0.9.2"),
    ],
    targets: [
        .target(
            name: "KadrCaptions",
            dependencies: [
                .product(name: "Kadr", package: "kadr"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KadrCaptionsTests",
            dependencies: ["KadrCaptions"]
        ),
    ]
)
