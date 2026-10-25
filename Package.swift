// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HyperVideoConverter",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "HyperVideoConverter", targets: ["HyperVideoConverter"])
    ],
    dependencies: [
        // In-app updates (MIT), like the other witchmymac apps.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .target(name: "HyperVideoCore"),
        .executableTarget(
            name: "HyperVideoConverter",
            dependencies: [
                "HyperVideoCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HyperVideoCoreTests",
            dependencies: ["HyperVideoCore"]
        ),
        .testTarget(
            name: "HyperVideoConverterTests",
            dependencies: ["HyperVideoConverter", "HyperVideoCore"]
        )
    ]
)
