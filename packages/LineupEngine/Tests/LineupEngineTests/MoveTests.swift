// LineupEngine.move(from:to:)

import XCTest
@testable import LineupEngine

final class MoveTests: XCTestCase {

    // MARK: - Range validation

    func testMoveFromNegativeThrowsPositionOutOfRange() throws {
        var engine = try Fixture.engine()
        assertThrows(.positionOutOfRange(-1), try engine.move(from: -1, to: 2))
    }

    func testMoveToFiveThrowsPositionOutOfRange() throws {
        var engine = try Fixture.engine()
        assertThrows(.positionOutOfRange(5), try engine.move(from: 2, to: 5))
    }

    // MARK: - No-op

    func testMoveFromEqualsToIsNoOp() throws {
        var engine = try Fixture.engine()
        let before = engine.currentOrder
        try engine.move(from: 2, to: 2)
        XCTAssertEqual(engine.currentOrder, before)
    }

    // MARK: - Simple shifting, everything unlocked

    func testMoveDownShiftsInBetweenTilesUp() throws {
        // [3,2,5,4,1] -> move position 0 to position 2 -> [2,5,3,4,1]
        var engine = try Fixture.engine()
        try engine.move(from: 0, to: 2)
        XCTAssertEqual(engine.currentOrder, [2, 5, 3, 4, 1])
    }

    func testMoveUpShiftsInBetweenTilesDown() throws {
        // [3,2,5,4,1] -> move position 4 to position 1 -> [3,1,2,5,4]
        var engine = try Fixture.engine()
        try engine.move(from: 4, to: 1)
        XCTAssertEqual(engine.currentOrder, [3, 1, 2, 5, 4])
    }

    // MARK: - Locked positions

    func testMoveFromLockedPositionThrowsPositionLocked() throws {
        var engine = try Fixture.engineAfterFirstLockingAttempt()
        XCTAssertEqual(engine.lockedPositions, [3, 4])
        assertThrows(.positionLocked(3), try engine.move(from: 3, to: 0))
    }

    func testMoveToLockedPositionThrowsPositionLocked() throws {
        var engine = try Fixture.engineAfterFirstLockingAttempt()
        XCTAssertEqual(engine.lockedPositions, [3, 4])
        assertThrows(.positionLocked(4), try engine.move(from: 0, to: 4))
    }

    func testMoveAmongUnlockedPositionsLeavesLockedTilesInPlace() throws {
        var engine = try Fixture.engineAfterFirstLockingAttempt()
        XCTAssertEqual(engine.currentOrder, [3, 1, 2, 4, 5])
        XCTAssertEqual(engine.lockedPositions, [3, 4])

        try engine.move(from: 0, to: 2)

        // Unlocked sub-list [3,1,2] at positions [0,1,2]: remove position 0's value
        // (3), insert it at position 2's rank (index 2) -> [1,2,3].
        XCTAssertEqual(engine.currentOrder, [1, 2, 3, 4, 5])
        // Locked tiles (ids 4, 5) never moved.
        XCTAssertEqual(engine.currentOrder[3], 4)
        XCTAssertEqual(engine.currentOrder[4], 5)
    }

    func testMoveAmongUnlockedPositionsWithThreeUnlockedSlots() throws {
        // A puzzle where the first submission locks positions 1 and 3 (ids 2, 4),
        // leaving positions 0, 2, 4 unlocked.
        var engine = try Fixture.engine(
            Fixture.puzzle(itemIDs: [3, 2, 5, 4, 1], correctOrder: [1, 2, 3, 4, 5])
        )
        try engine.move(from: 0, to: 4)
        try engine.move(from: 0, to: 1)
        try engine.move(from: 2, to: 3)
        XCTAssertEqual(engine.currentOrder, [5, 2, 1, 4, 3])
        try engine.submit(elapsedMs: 1_000)
        XCTAssertEqual(engine.lockedPositions, [1, 3])

        let before = engine.currentOrder // [5,2,1,4,3]
        try engine.move(from: 4, to: 0)

        // Locked tiles (ids 2, 4) at positions 1, 3 are untouched: the algorithm
        // only ever writes back into the unlocked positions.
        XCTAssertEqual(engine.currentOrder[1], 2)
        XCTAssertEqual(engine.currentOrder[3], 4)
        XCTAssertEqual(engine.currentOrder[1], before[1])
        XCTAssertEqual(engine.currentOrder[3], before[3])
        // The unlocked slots still hold the same set of ids, just rearranged.
        XCTAssertEqual(Set([engine.currentOrder[0], engine.currentOrder[2], engine.currentOrder[4]]),
                        Set([before[0], before[2], before[4]]))
        XCTAssertEqual(engine.currentOrder, [3, 2, 5, 4, 1])
    }

    // MARK: - After the puzzle ends

    func testMoveAfterSolveThrowsNotPlaying() throws {
        var engine = try Fixture.solvableEngine()
        try engine.submit(elapsedMs: 1_000)
        XCTAssertEqual(engine.phase, .solved)
        assertThrows(.notPlaying, try engine.move(from: 0, to: 1))
    }

    func testMoveAfterThreeFailingAttemptsThrowsNotPlaying() throws {
        var engine = try Fixture.engineAfterThreeFailingAttempts()
        XCTAssertEqual(engine.phase, .failed)
        assertThrows(.notPlaying, try engine.move(from: 0, to: 1))
    }
}
