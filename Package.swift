// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "kovim",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "kovim-agent", targets: ["KovimAgent"]),
        .executable(name: "kovim-im", targets: ["KovimIM"])
    ],
    targets: [
        .executableTarget(
            name: "KovimAgent",
            path: "Sources/KovimAgent"
        ),
        .executableTarget(
            name: "KovimIM",
            path: "cli"
        )
    ]
)
