// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinKey",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WinKey",
            path: "Sources/WinKey"
        )
    ]
)
