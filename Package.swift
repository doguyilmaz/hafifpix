// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HafifPix",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "HafifPixCore"),
        .executableTarget(
            name: "HafifPixApp",
            dependencies: ["HafifPixCore"]
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
