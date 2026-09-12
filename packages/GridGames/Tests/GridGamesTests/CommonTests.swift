// CommonTests.swift — GameKind, GridPoint, GameScoring, GameShareText.

import XCTest
@testable import GridGames

final class CommonTests: XCTestCase {

    // MARK: - GameKind

    func testAllCasesOrder() {
        XCTAssertEqual(GameKind.allCases, [.stars, .duo, .trail])
    }

    func testTitles() {
        XCTAssertEqual(GameKind.stars.title, "Stars")
        XCTAssertEqual(GameKind.duo.title, "Duo")
        XCTAssertEqual(GameKind.trail.title, "Trail")
    }

    func testSymbolNames() {
        XCTAssertEqual(GameKind.stars.symbolName, "star.fill")
        XCTAssertEqual(GameKind.duo.symbolName, "circle.lefthalf.filled")
        XCTAssertEqual(GameKind.trail.symbolName, "point.topleft.down.to.point.bottomright.curvepath")
    }

    // MARK: - GridPoint

    func testOrthogonalAdjacency() {
        let a = GridPoint(row: 2, col: 2)
        XCTAssertTrue(a.isOrthogonallyAdjacent(to: GridPoint(row: 1, col: 2)))
        XCTAssertTrue(a.isOrthogonallyAdjacent(to: GridPoint(row: 3, col: 2)))
        XCTAssertTrue(a.isOrthogonallyAdjacent(to: GridPoint(row: 2, col: 1)))
        XCTAssertTrue(a.isOrthogonallyAdjacent(to: GridPoint(row: 2, col: 3)))
        XCTAssertFalse(a.isOrthogonallyAdjacent(to: GridPoint(row: 1, col: 1)), "diagonal is not orthogonal")
        XCTAssertFalse(a.isOrthogonallyAdjacent(to: a), "self is not adjacent")
        XCTAssertFalse(a.isOrthogonallyAdjacent(to: GridPoint(row: 4, col: 2)), "two away")
    }

    func testTouches() {
        let a = GridPoint(row: 2, col: 2)
        XCTAssertFalse(a.touches(a), "self does not touch")
        XCTAssertTrue(a.touches(GridPoint(row: 1, col: 1)), "diagonal touches")
        XCTAssertTrue(a.touches(GridPoint(row: 3, col: 3)), "diagonal touches")
        XCTAssertTrue(a.touches(GridPoint(row: 1, col: 2)), "orthogonal also touches")
        XCTAssertFalse(a.touches(GridPoint(row: 1, col: 1)) && a.isOrthogonallyAdjacent(to: GridPoint(row: 1, col: 1)),
                       "diagonal touch is never orthogonal adjacency")
        XCTAssertFalse(a.touches(GridPoint(row: 4, col: 2)), "two away does not touch")
        XCTAssertFalse(a.touches(GridPoint(row: 0, col: 0)), "two away diagonally does not touch")
    }

    // MARK: - GameScoring

    func testScoreZero() {
        XCTAssertEqual(GameScoring.score(elapsedMs: 0, gaveUp: false), 1000)
    }

    func testScoreTenSeconds() {
        XCTAssertEqual(GameScoring.score(elapsedMs: 10_000, gaveUp: false), 980)
    }

    func testScoreAtCap() {
        XCTAssertEqual(GameScoring.score(elapsedMs: 450_000, gaveUp: false), 100)
    }

    func testScoreBeyondCap() {
        XCTAssertEqual(GameScoring.score(elapsedMs: 900_000, gaveUp: false), 100)
    }

    func testScoreGaveUp() {
        XCTAssertEqual(GameScoring.score(elapsedMs: 5_000, gaveUp: true), 100)
        XCTAssertEqual(GameScoring.score(elapsedMs: 900_000, gaveUp: true), 100)
    }

    func testScoreNegativeElapsed() {
        // Integer division truncates toward zero, so a small negative elapsed
        // divides to 0 seconds and scores like an instant solve.
        XCTAssertEqual(GameScoring.score(elapsedMs: -1, gaveUp: false), 1000)
        XCTAssertEqual(GameScoring.score(elapsedMs: -999, gaveUp: false), 1000)
    }

    // MARK: - GameShareText

    func testRenderStarsExample() {
        let text = GameShareText.render(game: .stars, number: 12, elapsedMs: 83_000, gaveUp: false,
                                         rows: ["⭐️⬛️"], refCode: "7F3Q")
        XCTAssertEqual(text, "Kith Stars #12 · 1:23\n⭐️⬛️\nkith.app/g/stars/12?r=7F3Q")
    }

    func testRenderGaveUp() {
        let text = GameShareText.render(game: .duo, number: 7, elapsedMs: 5_000, gaveUp: true,
                                         rows: ["X"], refCode: "AB12")
        XCTAssertEqual(text, "Kith Duo #7 · gave up\nX\nkith.app/g/duo/7?r=AB12")
    }

    func testRenderEmptyRows() {
        let text = GameShareText.render(game: .stars, number: 1, elapsedMs: 5_000, gaveUp: false,
                                         rows: [], refCode: nil)
        XCTAssertEqual(text, "Kith Stars #1 · 0:05\nkith.app/g/stars/1")
    }

    func testRenderNilRefCode() {
        let text = GameShareText.render(game: .trail, number: 3, elapsedMs: 61_000, gaveUp: false,
                                         rows: ["🟩"], refCode: nil)
        XCTAssertEqual(text, "Kith Trail #3 · 1:01\n🟩\nkith.app/g/trail/3")
    }

    func testRenderEmptyRefCode() {
        let text = GameShareText.render(game: .trail, number: 3, elapsedMs: 61_000, gaveUp: false,
                                         rows: ["🟩"], refCode: "")
        XCTAssertEqual(text, "Kith Trail #3 · 1:01\n🟩\nkith.app/g/trail/3")
    }

    func testRenderSecondsPadding() {
        let text = GameShareText.render(game: .stars, number: 1, elapsedMs: 5_000, gaveUp: false,
                                         rows: [], refCode: nil)
        XCTAssertTrue(text.contains("· 0:05"))
    }

    func testRenderTwelveMinutesFlat() {
        let text = GameShareText.render(game: .stars, number: 1, elapsedMs: 720_000, gaveUp: false,
                                         rows: [], refCode: nil)
        XCTAssertTrue(text.contains("· 12:00"))
    }
}
