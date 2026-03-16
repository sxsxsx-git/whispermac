// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "whispermac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "whispermac", targets: ["whispermac"]),
    ],
    targets: [
        .executableTarget(
            name: "whispermac"
        ),
        .testTarget(
            name: "whispermacTests",
            dependencies: ["whispermac"]
        ),
    ]
)
