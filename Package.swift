// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HyperVideoConverter",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "HyperVideoConverter", targets: ["HyperVideoConverter"])
    ],
    targets: [
        .target(name: "HyperVideoCore"),
        .executableTarget(
            name: "HyperVideoConverter",
            dependencies: ["HyperVideoCore"]
        ),
        .testTarget(
            name: "HyperVideoCoreTests",
            dependencies: ["HyperVideoCore"]
        )
    ]
)
