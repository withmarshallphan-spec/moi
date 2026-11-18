// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Moi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Moi", targets: ["MoiApp"])
    ],
    targets: [
        .executableTarget(
            name: "MoiApp",
            path: "Sources/MoiApp",
            resources: [.process("Resources")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
