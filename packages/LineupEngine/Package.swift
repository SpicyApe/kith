// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LineupEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LineupEngine", targets: ["LineupEngine"]),
    ],
    targets: [
        .target(name: "LineupEngine", path: "Sources/LineupEngine"),
        .testTarget(
            name: "LineupEngineTests",
            dependencies: ["LineupEngine"],
            path: "Tests/LineupEngineTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
