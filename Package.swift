// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DualSpine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "DualSpineCore", targets: ["DualSpineCore"]),
        .library(name: "DualSpineRender", targets: ["DualSpineRender"]),
        .library(name: "DualSpineSemantic", targets: ["DualSpineSemantic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.6"),
    ],
    targets: [
        .target(
            name: "DualSpineCore",
            dependencies: ["ZIPFoundation", "SwiftSoup"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DualSpineRender",
            dependencies: ["DualSpineCore", "SwiftSoup"],
            resources: [
                .copy("Resources/reader-controller.js"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DualSpineSemantic",
            dependencies: ["DualSpineCore", "SwiftSoup"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DualSpineCoreTests",
            dependencies: ["DualSpineCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DualSpineSemanticTests",
            dependencies: ["DualSpineSemantic"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
