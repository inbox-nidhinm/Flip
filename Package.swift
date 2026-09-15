// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flip",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Flip",
            path: "Sources/Flip",
            // Copied rather than processed: the grain is a repacked grey+alpha
            // PNG and any re-encoding on the way in would undo that.
            resources: [.copy("Textures"), .copy("Fonts"), .copy("Onboarding")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
