// DuoTests.swift — Tango-style 6x6 binary grid engine.

import XCTest
@testable import GridGames

final class DuoTests: XCTestCase {

    // A valid 6x6 Takuzu solution: each row/column has three 0s and three 1s and no
    // three consecutive equal cells horizontally or vertically. Verified by hand and
    // re-checked programmatically below.
    static let solvedGrid: [[Int]] = [
        [0, 0, 1, 1, 0, 1],
        [1, 1, 0, 0, 1, 0],
        [0, 1, 0, 1, 1, 0],
        [1, 0, 1, 0, 0, 1],
        [1, 0, 0, 1, 0, 1],
        [0, 1, 1, 0, 1, 0],
    ]

    /// Sanity-check the fixture itself: three of each symbol per row/column, no triples.
    func testFixtureGridIsValid() {
        let grid = Self.solvedGrid
        let n = 6
        for r in 0..<n {
            let row = grid[r]
            XCTAssertEqual(row.filter { $0 == 0 }.count, 3, "row \(r) should have three 0s")
            XCTAssertEqual(row.filter { $0 == 1 }.count, 3, "row \(r) should have three 1s")
            for c in 0...(n - 3) {
                XCTAssertFalse(row[c] == row[c + 1] && row[c + 1] == row[c + 2],
                                "row \(r) has a triple starting at col \(c)")
            }
        }
        for c in 0..<n {
            let col = (0..<n).map { grid[$0][c] }
            XCTAssertEqual(col.filter { $0 == 0 }.count, 3, "col \(c) should have three 0s")
            XCTAssertEqual(col.filter { $0 == 1 }.count, 3, "col \(c) should have three 1s")
            for r in 0...(n - 3) {
                XCTAssertFalse(col[r] == col[r + 1] && col[r + 1] == col[r + 2],
                                "col \(c) has a triple starting at row \(r)")
            }
        }
    }

    static func givens(diagonalOnly grid: [[Int]]) -> [[Int?]] {
        (0..<6).map { r in
            (0..<6).map { c in r == c ? grid[r][c] : nil }
        }
    }

    // (0,0)=0 and (0,1)=0 are equal & adjacent; (0,1)=0 and (0,2)=1 differ & are adjacent.
    static func goldenSpec() -> DuoSpec {
        DuoSpec(n: 6, givens: givens(diagonalOnly: solvedGrid), eq: [[0, 0, 0, 1]], ne: [[0, 1, 0, 2]])
    }

    func blankSpec(eq: [[Int]] = [], ne: [[Int]] = []) -> DuoSpec {
        DuoSpec(n: 6, givens: Array(repeating: Array(repeating: nil, count: 6), count: 6), eq: eq, ne: ne)
    }

    // MARK: - init validation

    func testInitRejectsWrongN() {
        let spec = DuoSpec(n: 5, givens: Array(repeating: Array(repeating: nil, count: 5), count: 5), eq: [], ne: [])
        XCTAssertThrowsError(try DuoEngine(spec: spec))
    }

    func testInitRejectsBadGivenValue() {
        var givens = Self.givens(diagonalOnly: Self.solvedGrid)
        givens[0][0] = 2
        let spec = DuoSpec(n: 6, givens: givens, eq: [], ne: [])
        XCTAssertThrowsError(try DuoEngine(spec: spec))
    }

    func testInitRejectsNonAdjacentConstraint() {
        let spec = blankSpec(eq: [[0, 0, 2, 2]])
        XCTAssertThrowsError(try DuoEngine(spec: spec))
    }

    func testInitAcceptsGoldenSpec() {
        XCTAssertNoThrow(try DuoEngine(spec: Self.goldenSpec()))
    }

    // MARK: - givens

    func testIsGiven() throws {
        let engine = try DuoEngine(spec: Self.goldenSpec())
        for i in 0..<6 {
            XCTAssertTrue(engine.isGiven(at: GridPoint(row: i, col: i)))
        }
        XCTAssertFalse(engine.isGiven(at: GridPoint(row: 0, col: 1)))
    }

    // MARK: - cycle / no-op on givens

    func testCycleOrder() throws {
        var engine = try DuoEngine(spec: blankSpec())
        let p = GridPoint(row: 2, col: 3)
        XCTAssertNil(engine.cells[2][3])
        try engine.cycle(at: p)
        XCTAssertEqual(engine.cells[2][3], 0)
        try engine.cycle(at: p)
        XCTAssertEqual(engine.cells[2][3], 1)
        try engine.cycle(at: p)
        XCTAssertNil(engine.cells[2][3])
    }

    func testCycleNoOpOnGiven() throws {
        var engine = try DuoEngine(spec: Self.goldenSpec())
        let p = GridPoint(row: 0, col: 0)
        XCTAssertEqual(engine.cells[0][0], 0)
        try engine.cycle(at: p)
        XCTAssertEqual(engine.cells[0][0], 0, "given cells never change")
    }

    func testCycleOutOfBounds() throws {
        var engine = try DuoEngine(spec: blankSpec())
        XCTAssertThrowsError(try engine.cycle(at: GridPoint(row: -1, col: 0))) { error in
            XCTAssertEqual(error as? GridError, .outOfBounds)
        }
    }

    // MARK: - conflicts

    func testConflictsThreeInARowHorizontal() throws {
        var engine = try DuoEngine(spec: blankSpec())
        try engine.set(0, at: GridPoint(row: 0, col: 0))
        try engine.set(0, at: GridPoint(row: 0, col: 1))
        try engine.set(0, at: GridPoint(row: 0, col: 2))
        XCTAssertEqual(engine.conflicts, Set([
            GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1), GridPoint(row: 0, col: 2),
        ]))
    }

    func testConflictsThreeInARowVertical() throws {
        var engine = try DuoEngine(spec: blankSpec())
        try engine.set(1, at: GridPoint(row: 0, col: 0))
        try engine.set(1, at: GridPoint(row: 1, col: 0))
        try engine.set(1, at: GridPoint(row: 2, col: 0))
        XCTAssertEqual(engine.conflicts, Set([
            GridPoint(row: 0, col: 0), GridPoint(row: 1, col: 0), GridPoint(row: 2, col: 0),
        ]))
    }

    func testConflictsFourOfOneSymbolInRow() throws {
        var engine = try DuoEngine(spec: blankSpec())
        // Four 0s in row 0 at columns 0,1,3,4 (gap at col 2 avoids a triple).
        try engine.set(0, at: GridPoint(row: 0, col: 0))
        try engine.set(0, at: GridPoint(row: 0, col: 1))
        try engine.set(0, at: GridPoint(row: 0, col: 3))
        try engine.set(0, at: GridPoint(row: 0, col: 4))
        XCTAssertEqual(engine.conflicts, Set([
            GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1),
            GridPoint(row: 0, col: 3), GridPoint(row: 0, col: 4),
        ]))
    }

    func testConflictsEqViolationOnlyWhenBothFilled() throws {
        var engine = try DuoEngine(spec: blankSpec(eq: [[0, 0, 0, 1]]))
        try engine.set(0, at: GridPoint(row: 0, col: 0))
        XCTAssertTrue(engine.conflicts.isEmpty, "eq is not evaluated until both cells are filled")

        try engine.set(1, at: GridPoint(row: 0, col: 1))
        XCTAssertEqual(engine.conflicts, Set([GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1)]))
    }

    func testConflictsNeViolationOnlyWhenBothFilled() throws {
        var engine = try DuoEngine(spec: blankSpec(ne: [[0, 0, 0, 1]]))
        try engine.set(0, at: GridPoint(row: 0, col: 0))
        XCTAssertTrue(engine.conflicts.isEmpty, "ne is not evaluated until both cells are filled")

        try engine.set(0, at: GridPoint(row: 0, col: 1))
        XCTAssertEqual(engine.conflicts, Set([GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1)]))
    }

    // MARK: - completion / answer / shareRows

    func testCompleteGrid() throws {
        var engine = try DuoEngine(spec: Self.goldenSpec())
        for r in 0..<6 {
            for c in 0..<6 {
                try engine.set(Self.solvedGrid[r][c], at: GridPoint(row: r, col: c))
            }
        }
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.answer, Self.solvedGrid)
        XCTAssertEqual(engine.shareRows(), [
            "●●○○●○",
            "○○●●○●",
            "●○●○○●",
            "○●○●●○",
            "○●●○●○",
            "●○○●○●",
        ])
    }

    func testPartialGridIsIncomplete() throws {
        var engine = try DuoEngine(spec: Self.goldenSpec())
        try engine.set(0, at: GridPoint(row: 0, col: 2))
        XCTAssertFalse(engine.isComplete)
        XCTAssertNil(engine.answer)
    }

    func testResetKeepsGivens() throws {
        var engine = try DuoEngine(spec: Self.goldenSpec())
        try engine.set(1, at: GridPoint(row: 0, col: 1))
        engine.reset()
        for i in 0..<6 {
            XCTAssertEqual(engine.cells[i][i], Self.solvedGrid[i][i], "given retained")
        }
        XCTAssertNil(engine.cells[0][1], "non-given cleared")
    }
}
