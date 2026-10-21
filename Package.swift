// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AltTabber",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AltTabber",
            path: "Sources/AltTabber",
            linkerSettings: [.unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])]
        ),
    ]
)
