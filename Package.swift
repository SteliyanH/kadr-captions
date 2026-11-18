// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KadrCaptions",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "KadrCaptions", targets: ["KadrCaptions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SteliyanH/kadr.git", from: "1.2.0"),
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
        // The README's ```swift blocks, copied here by Tools/readme-snippets.sh
        // so they compile against the API they demonstrate. Not a product.
        .target(
            name: "KadrCaptionsExamples",
            dependencies: [
                "KadrCaptions",
                .product(name: "Kadr", package: "kadr"),
            ],
            path: "Examples",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KadrCaptionsTests",
            dependencies: ["KadrCaptions"]
        ),
    ]
)
