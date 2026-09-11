// swift-tools-version: 5.9
import PackageDescription

// KithCore: everything in the iOS client that is not a view. Platform-neutral so it
// builds and tests on Linux/Windows toolchains as well as Xcode. No CryptoKit, no
// Contacts, no UIKit; the app target injects those behind protocols.
let package = Package(
    name: "KithCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KithCore", targets: ["KithCore"]),
    ],
    dependencies: [
        .package(path: "../LineupEngine"),
    ],
    targets: [
        .target(name: "KithCore", dependencies: ["LineupEngine"], path: "Sources/KithCore"),
        .testTarget(name: "KithCoreTests", dependencies: ["KithCore", "LineupEngine"], path: "Tests/KithCoreTests"),
    ]
)
