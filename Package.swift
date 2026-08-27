// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RankFolderCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RankFolderCore", targets: ["RankFolderCore"])
    ],
    targets: [
        .target(
            name: "RankFolderCore",
            path: "Shared"
        ),
        .testTarget(
            name: "RankFolderCoreTests",
            dependencies: ["RankFolderCore"],
            path: "Tests"
        )
    ]
)

