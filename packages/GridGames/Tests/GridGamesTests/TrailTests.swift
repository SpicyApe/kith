// TrailTests.swift — Zip-style path engine.

import XCTest
@testable import GridGames

final class TrailTests: XCTestCase {

    // 3x3, waypoints at (0,0) -> (1,1) -> (2,2). One valid Hamiltonian solution:
    // (0,0)(0,1)(0,2)(1,2)(1,1)(1,0)(2,0)(2,1)(2,2)
    // The middle waypoint (1,1) is visited at index 4.
    static func goldenSpec() -> TrailSpec {
        TrailSpec(n: 3, waypoints: [[0, 0], [1, 1], [2, 2]])
    }
    static let solutionPath: [GridPoint] = [
        GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1), GridPoint(row: 0, col: 2),
        GridPoint(row: 1, col: 2), GridPoint(row: 1, col: 1), GridPoint(row: 1, col: 0),
        GridPoint(row: 2, col: 0), GridPoint(row: 2, col: 1), GridPoint(row: 2, col: 2),
    ]

    // MARK: - init validation

    func testInitRejectsTooSmallN() {
        let spec = TrailSpec(n: 2, waypoints: [[0, 0], [1, 1]])
        XCTAssertThrowsError(try TrailEngine(spec: spec))
    }

    func testInitRejectsSingleWaypoint() {
        let spec = TrailSpec(n: 3, waypoints: [[0, 0]])
        XCTAssertThrowsError(try TrailEngine(spec: spec))
    }

    func testInitRejectsDuplicateWaypoints() {
        let spec = TrailSpec(n: 3, waypoints: [[0, 0], [0, 0], [2, 2]])
        XCTAssertThrowsError(try TrailEngine(spec: spec))
    }

    func testInitRejectsOutOfRangeWaypoint() {
        let spec = TrailSpec(n: 3, waypoints: [[0, 0], [5, 5]])
        XCTAssertThrowsError(try TrailEngine(spec: spec))
    }

    func testInitAcceptsGoldenSpec() {
        XCTAssertNoThrow(try TrailEngine(spec: Self.goldenSpec()))
    }

    // MARK: - initial state

    func testInitialState() throws {
        let engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0)])
        XCTAssertEqual(engine.nextWaypoint, 2)
        XCTAssertEqual(engine.visited, Set([GridPoint(row: 0, col: 0)]))
    }

    func testWaypointNumberAt() throws {
        let engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertEqual(engine.waypointNumber(at: GridPoint(row: 0, col: 0)), 1)
        XCTAssertEqual(engine.waypointNumber(at: GridPoint(row: 1, col: 1)), 2)
        XCTAssertEqual(engine.waypointNumber(at: GridPoint(row: 2, col: 2)), 3)
        XCTAssertNil(engine.waypointNumber(at: GridPoint(row: 0, col: 1)))
    }

    // MARK: - extend rules

    func testExtendToNonAdjacentFails() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertFalse(engine.extend(to: GridPoint(row: 2, col: 2)))
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0)])
    }

    func testExtendToVisitedFails() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 1)))
        XCTAssertFalse(engine.extend(to: GridPoint(row: 0, col: 1)))
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1)])
    }

    func testExtendToLaterWaypointBeforeNextRequiredFails() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        // Walk to (1,2), which is adjacent to waypoint 3 at (2,2) -- but waypoint 2
        // at (1,1) hasn't been visited yet, so stepping onto (2,2) must fail.
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 1)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 2)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 1, col: 2)))
        XCTAssertEqual(engine.nextWaypoint, 2)

        XCTAssertFalse(engine.extend(to: GridPoint(row: 2, col: 2)))
        XCTAssertEqual(engine.path, [
            GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1),
            GridPoint(row: 0, col: 2), GridPoint(row: 1, col: 2),
        ])
    }

    func testValidStepsGrowThePath() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        for (i, point) in Self.solutionPath.enumerated() where i > 0 {
            XCTAssertTrue(engine.extend(to: point), "step \(i) to \(point) should succeed")
            XCTAssertEqual(engine.path, Array(Self.solutionPath.prefix(i + 1)))
        }
        XCTAssertEqual(engine.nextWaypoint, 4)
        XCTAssertTrue(engine.isComplete)
    }

    func testDragBackRetractsOneStep() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 1)))
        XCTAssertEqual(engine.path.count, 2)

        // Dragging back onto the previous cell retracts one step and returns true.
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 0)))
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0)])
    }

    // MARK: - retract(to:)

    func testRetractTruncatesButKeepsFirstCell() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 1)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 2)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 1, col: 2)))
        XCTAssertEqual(engine.path.count, 4)

        engine.retract(to: GridPoint(row: 0, col: 1))
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1)])

        // Not on the path: no-op.
        engine.retract(to: GridPoint(row: 2, col: 2))
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1)])

        // Retracting to the first cell keeps it (never removed).
        engine.retract(to: GridPoint(row: 0, col: 0))
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0)])
    }

    // MARK: - completion / answer / shareRows

    func testCompletingTheSnake() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        for point in Self.solutionPath.dropFirst() {
            XCTAssertTrue(engine.extend(to: point))
        }
        XCTAssertTrue(engine.isComplete)
        XCTAssertEqual(engine.answer, Self.solutionPath.map { [$0.row, $0.col] })
        XCTAssertEqual(engine.nextWaypoint, 4)
        XCTAssertEqual(engine.shareRows(), ["🟩🟩🟩"])
    }

    func testWrongFinalCellIsIncomplete() throws {
        // A different 3x3 spec with only two waypoints (opposite corners of row 0), so a
        // full-coverage path can visit the last waypoint mid-path and end elsewhere.
        let spec = TrailSpec(n: 3, waypoints: [[0, 0], [0, 2]])
        var engine = try TrailEngine(spec: spec)
        let path = [
            GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1), GridPoint(row: 0, col: 2),
            GridPoint(row: 1, col: 2), GridPoint(row: 1, col: 1), GridPoint(row: 1, col: 0),
            GridPoint(row: 2, col: 0), GridPoint(row: 2, col: 1), GridPoint(row: 2, col: 2),
        ]
        for point in path.dropFirst() {
            XCTAssertTrue(engine.extend(to: point))
        }
        // All 9 cells are covered, but the path ends at (2,2), not the last waypoint (0,2).
        XCTAssertFalse(engine.isComplete)
    }

    func testRetractBeforeWaypointGatesReExtendingPastIt() throws {
        // Walk past waypoint 2 (1,1) to (1,0), then retract to a point before
        // waypoint 2 is on the path. nextWaypoint must correctly report 2 again
        // (not still think waypoint 2 was reached), so stepping straight to
        // waypoint 3 (2,2) is rejected until waypoint 2 is revisited.
        var engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 1)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 2)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 1, col: 2)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 1, col: 1))) // waypoint 2
        XCTAssertEqual(engine.nextWaypoint, 3)
        XCTAssertTrue(engine.extend(to: GridPoint(row: 1, col: 0)))
        XCTAssertEqual(engine.nextWaypoint, 3)

        engine.retract(to: GridPoint(row: 1, col: 2))
        XCTAssertEqual(engine.path, [
            GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1),
            GridPoint(row: 0, col: 2), GridPoint(row: 1, col: 2),
        ])
        XCTAssertEqual(engine.nextWaypoint, 2)

        XCTAssertFalse(engine.extend(to: GridPoint(row: 2, col: 2)))
        XCTAssertEqual(engine.nextWaypoint, 2)
    }

    func testResetReturnsToStart() throws {
        var engine = try TrailEngine(spec: Self.goldenSpec())
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 1)))
        XCTAssertTrue(engine.extend(to: GridPoint(row: 0, col: 2)))
        engine.reset()
        XCTAssertEqual(engine.path, [GridPoint(row: 0, col: 0)])
        XCTAssertEqual(engine.nextWaypoint, 2)
        XCTAssertEqual(engine.visited, Set([GridPoint(row: 0, col: 0)]))
    }
}
