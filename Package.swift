// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "proof",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "proof", targets: ["proof"]),
        .library(name: "ProofKit", targets: ["ProofKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "ProofKit"),
        .executableTarget(
            name: "proof",
            dependencies: [
                "ProofKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ProofKitTests",
            dependencies: ["ProofKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
