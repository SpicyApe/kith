// swift-tools-version: 5.9
import PackageDescription

// GridGames: pure, UI-free engines for Stars, Duo and Trail (docs/07-games-hub.md).
// Platform-neutral so it builds and tests on any Swift toolchain. Mirrors the
// TypeScript validators in supabase/functions/_shared/games via a golden fixture.
let package = Package(
    name: "GridGames",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GridGames", targets: ["GridGames"]),
    ],
    targets: [
        .target(name: "GridGames", path: "Sources/GridGames"),
        .testTarget(name: "GridGamesTests", dependencies: ["GridGames"], path: "Tests/GridGamesTests",
                    resources: [.copy("Fixtures")]),
    ]
)
