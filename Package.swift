// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "whispermac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "whispermac", targets: ["whispermac"]),
    ],
    targets: [
        .executableTarget(
            name: "whispermac",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "whispermacTests",
            dependencies: ["whispermac"]
        ),
    ]
)
