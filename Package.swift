// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CVAutoFill",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CVAutoFill",
            path: "Sources/CVAutoFill",
            resources: [.copy("Resources/logo.png")]
        )
    ]
)
