// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KitMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "KitMenuBar",
            path: "Sources/KitMenuBar"
        )
    ]
)
