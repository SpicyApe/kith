// StarsTests.swift — Queens-style Stars engine.

import XCTest
@testable import GridGames

final class StarsTests: XCTestCase {

    // 5x5 fixture. Stars at columns [1,3,0,2,4] for rows 0..4. Regions are simply
    // "one region per row" (regions[r][c] == r for all c): this trivially satisfies
    // "every id 0..<n present" and "star's cell has region == row index" and, per the
    // contract, StarsEngine does not require region connectivity.
    static let starColumns = [1, 3, 0, 2, 4]
    static func goldenRegions(n: Int = 5) -> [[Int]] {
        (0..<n).map { r in Array(repeating: r, count: n) }
    }
    static func goldenSpec() -> StarsSpec {
        StarsSpec(n: 5, regions: goldenRegions())
    }

    func goldenEngineWithAllStars() throws -> StarsEngine {
        var engine = try StarsEngine(spec: Self.goldenSpec())
        for row in 0..<5 {
            try engine.set(.star, at: GridPoint(row: row, col: Self.starColumns[row]))
        }
        return engine
    }

    // MARK: - init validation

    func testInitRejectsTooSmallN() {
        let spec = StarsSpec(n: 3, regions: [[0, 0, 1], [0, 1, 1], [2, 2, 2]])
        XCTAssertThrowsError(try StarsEngine(spec: spec)) { error in
            guard case GridError.invalidSpec = error else {
                return XCTFail("expected invalidSpec, got \(error)")
            }
        }
    }

    func testInitRejectsNonSquareRegions() {
        // Only 4 rows for n = 5.
        let spec = StarsSpec(n: 5, regions: [[0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [2, 2, 2, 2, 2], [3, 3, 3, 3, 3]])
        XCTAssertThrowsError(try StarsEngine(spec: spec))
    }

    func testInitRejectsRaggedRow() {
        var regions = Self.goldenRegions()
        regions[2] = [2, 2, 2, 2] // wrong length row
        let spec = StarsSpec(n: 5, regions: regions)
        XCTAssertThrowsError(try StarsEngine(spec: spec))
    }

    func testInitRejectsOutOfRangeId() {
        var regions = Self.goldenRegions()
        regions[0][0] = 5 // valid ids are 0..<5
        let spec = StarsSpec(n: 5, regions: regions)
        XCTAssertThrowsError(try StarsEngine(spec: spec))
    }

    func testInitRejectsMissingId() {
        // Only ids 0...3 appear; id 4 is missing entirely.
        let regions = [
            [0, 0, 0, 0, 0],
            [1, 1, 1, 1, 1],
            [2, 2, 2, 2, 2],
            [3, 3, 3, 3, 3],
            [3, 3, 3, 3, 3],
        ]
        let spec = StarsSpec(n: 5, regions: regions)
        XCTAssertThrowsError(try StarsEngine(spec: spec))
    }

    func testInitAcceptsGoldenSpec() throws {
        XCTAssertNoThrow(try StarsEngine(spec: Self.goldenSpec()))
    }

    // MARK: - cycle / set / reset

    func testCycleOrder() throws {
        var engine = try StarsEngine(spec: Self.goldenSpec())
        let p = GridPoint(row: 0, col: 0)
        XCTAssertEqual(engine.marks[0][0], .empty)
        try engine.cycle(at: p)
        XCTAssertEqual(engine.marks[0][0], .cross)
        try engine.cycle(at: p)
        XCTAssertEqual(engine.marks[0][0], .star)
        try engine.cycle(at: p)
        XCTAssertEqual(engine.marks[0][0], .empty)
    }

    func testSetAndOutOfBounds() throws {
        var engine = try StarsEngine(spec: Self.goldenSpec())
        try engine.set(.star, at: GridPoint(row: 1, col: 1))
        XCTAssertEqual(engine.marks[1][1], .star)

        XCTAssertThrowsError(try engine.set(.star, at: GridPoint(row: -1, col: 0))) { error in
            XCTAssertEqual(error as? GridError, .outOfBounds)
        }
        XCTAssertThrowsError(try engine.set(.star, at: GridPoint(row: 0, col: 5))) { error in
            XCTAssertEqual(error as? GridError, .outOfBounds)
        }
        XCTAssertThrowsError(try engine.cycle(at: GridPoint(row: 10, col: 10))) { error in
            XCTAssertEqual(error as? GridError, .outOfBounds)
        }
    }

    func testResetClears() throws {
        var engine = try StarsEngine(spec: Self.goldenSpec())
        try engine.set(.star, at: GridPoint(row: 0, col: 0))
        try engine.set(.cross, at: GridPoint(row: 1, col: 1))
        engine.reset()
        for row in engine.marks {
            for mark in row {
                XCTAssertEqual(mark, .empty)
            }
        }
        XCTAssertEqual(engine.starCount, 0)
    }

    // MARK: - conflicts

    func testConflictsSameRowOnly() throws {
        // regions keyed by column so same-row stars land in different regions.
        let regions = (0..<5).map { _ in Array(0..<5) }
        var engine = try StarsEngine(spec: StarsSpec(n: 5, regions: regions))
        try engine.set(.star, at: GridPoint(row: 0, col: 0))
        try engine.set(.star, at: GridPoint(row: 0, col: 2))
        XCTAssertEqual(engine.conflicts, Set([GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 2)]))
    }

    func testConflictsSameColumnOnly() throws {
        // regions keyed by row so same-column stars land in different regions.
        let regions = Self.goldenRegions()
        var engine = try StarsEngine(spec: StarsSpec(n: 5, regions: regions))
        try engine.set(.star, at: GridPoint(row: 0, col: 0))
        try engine.set(.star, at: GridPoint(row: 2, col: 0))
        XCTAssertEqual(engine.conflicts, Set([GridPoint(row: 0, col: 0), GridPoint(row: 2, col: 0)]))
    }

    func testConflictsSameRegionOnly() throws {
        // (0,0) and (2,2) share region 0; ids 1..4 appear once each in the last row.
        let regions = [
            [0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0],
            [1, 2, 3, 4, 0],
        ]
        var engine = try StarsEngine(spec: StarsSpec(n: 5, regions: regions))
        try engine.set(.star, at: GridPoint(row: 0, col: 0))
        try engine.set(.star, at: GridPoint(row: 2, col: 2))
        XCTAssertEqual(engine.conflicts, Set([GridPoint(row: 0, col: 0), GridPoint(row: 2, col: 2)]))
    }

    func testConflictsDiagonalTouch() throws {
        let regions = [
            [0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0],
            [0, 0, 2, 0, 0],
            [0, 0, 0, 3, 0],
            [4, 0, 0, 0, 0],
        ]
        var engine = try StarsEngine(spec: StarsSpec(n: 5, regions: regions))
        try engine.set(.star, at: GridPoint(row: 1, col: 1))
        try engine.set(.star, at: GridPoint(row: 2, col: 2))
        XCTAssertEqual(engine.conflicts, Set([GridPoint(row: 1, col: 1), GridPoint(row: 2, col: 2)]))
    }

    func testNoConflictsWhenValid() throws {
        let engine = try goldenEngineWithAllStars()
        XCTAssertTrue(engine.conflicts.isEmpty)
    }

    // MARK: - completion / answer / shareRows

    func testIsCompleteFalseWithFourStars() throws {
        var engine = try StarsEngine(spec: Self.goldenSpec())
        for row in 0..<4 {
            try engine.set(.star, at: GridPoint(row: row, col: Self.starColumns[row]))
        }
        XCTAssertEqual(engine.starCount, 4)
        XCTAssertFalse(engine.isComplete)
        XCTAssertNil(engine.answer)
    }

    func testIsCompleteTrueWithFiveStars() throws {
        let engine = try goldenEngineWithAllStars()
        XCTAssertEqual(engine.starCount, 5)
        XCTAssertTrue(engine.isComplete)
    }

    func testAnswerMatchesStarColumns() throws {
        let engine = try goldenEngineWithAllStars()
        XCTAssertEqual(engine.answer, Self.starColumns)
    }

    func testShareRowsForCompleteGrid() throws {
        let engine = try goldenEngineWithAllStars()
        let expected = [
            "⬛️⭐️⬛️⬛️⬛️",
            "⬛️⬛️⬛️⭐️⬛️",
            "⭐️⬛️⬛️⬛️⬛️",
            "⬛️⬛️⭐️⬛️⬛️",
            "⬛️⬛️⬛️⬛️⭐️",
        ]
        XCTAssertEqual(engine.shareRows(), expected)
    }
}
