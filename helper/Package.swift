// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EchoTypeHelper",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .executableTarget(
            name: "EchoTypeHelper",
            dependencies: [
                .product(name: "CoreKit", package: "CoreKit")
            ]
        )
    ]
)
