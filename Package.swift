// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PBNCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PBNCore",
            targets: ["PBNCore"]
        )
    ],
    targets: [
        .target(
            name: "PBNCore",
            path: "Sources/PBNCore"
        ),
        .testTarget(
            name: "PBNCoreTests",
            dependencies: ["PBNCore"],
            path: "Tests/PBNCoreTests"
        )
    ]
)
