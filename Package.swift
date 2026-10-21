// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AltTab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AltTab",
            path: "Sources/AltTab",
            linkerSettings: [.unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])]
        ),
    ]
)
