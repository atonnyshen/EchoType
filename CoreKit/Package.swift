// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"])
    ],
    dependencies: [
        // SQLite wrapper
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "CoreKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"]
        )
    ]
)
