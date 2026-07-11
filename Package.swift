// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HafifPix",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "HafifPixCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "HafifPixApp",
            dependencies: [
                "HafifPixCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "hafif",
            dependencies: ["HafifPixCore"]
        ),
        .testTarget(
            name: "HafifPixCoreTests",
            dependencies: ["HafifPixCore"]
        ),
    ]
)
