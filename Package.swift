// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "guardian",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "guardian", targets: ["Guardian"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Guardian",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Guardian"
        ),
        .testTarget(
            name: "GuardianTests",
            dependencies: ["Guardian"],
            path: "Tests/GuardianTests"
        ),
    ]
)
