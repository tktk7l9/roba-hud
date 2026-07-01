// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "roba-hud",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RoBaHUD",
            path: "Sources/RoBaHUD"
        )
    ]
)
