// LineupEngine.canSubmit and LineupEngine.submit(elapsedMs:)

import XCTest
@testable import LineupEngine

final class SubmitTests: XCTestCase {

    // MARK: - canSubmit

    func testCanSubmitFalseInitially() throws {
        let engine = try Fixture.engine()
        XCTAssertFalse(engine.canSubmit)
    }

    func testCanSubmitTrueAfterMove() throws {
        var engine = try Fixture.engine()
        try engine.move(from: 0, to: 1)
        XCTAssertTrue(engine.canSubmit)
    }

    func testCanSubmitFalseAfterMovingBackToInitialOrder() throws {
        var engine = try Fixture.engine()
        try engine.move(from: 0, to: 1)
        try engine.move(from: 1, to: 0)
        XCTAssertEqual(engine.currentOrder, Fixture.puzzle().items.map(\.id))
        XCTAssertFalse(engine.canSubmit)
    }

    func testCanSubmitFalseAfterSubmissionUntilOrderChanges() throws {
        var engine = try Fixture.engine()
        try engine.move(from: 0, to: 1)
        try engine.submit(elapsedMs: 1_000)

        XCTAssertFalse(engine.canSubmit)

        try engine.move(from: 0, to: 1)
        XCTAssertTrue(engine.canSubmit)
    }

    // MARK: - submit validation

    func testSubmitThrowsNothingChangedWhenCanSubmitIsFalse() throws {
        var engine = try Fixture.engine()
        XCTAssertFalse(engine.canSubmit)
        assertThrows(.nothingChanged, try engine.submit(elapsedMs: 1_000))
    }

    func testSubmitThrowsInvalidElapsedForNegative() throws {
        var engine = try Fixture.engine()
        try engine.move(from: 0, to: 1)
        assertThrows(.invalidElapsed, try engine.submit(elapsedMs: -1))
        XCTAssertTrue(engine.attempts.isEmpty)
    }

    func testSubmitThrowsInvalidElapsedWhenLowerThanPreviousAttempt() throws {
        var engine = try Fixture.engine()
        try engine.move(from: 0, to: 1)
        try engine.submit(elapsedMs: 5_000)

        try engine.move(from: 0, to: 4)
        XCTAssertTrue(engine.canSubmit)

        assertThrows(.invalidElapsed, try engine.submit(elapsedMs: 4_000))
        XCTAssertEqual(engine.attempts.count, 1)
    }

    // MARK: - Outcomes

    func testSubmitSolvedOnFirstTry() throws {
        var engine = try Fixture.solvableEngine()
        let attempt = try engine.submit(elapsedMs: 7_000)

        XCTAssertTrue(attempt.isSolved)
        XCTAssertEqual(engine.phase, .solved)

        let result = try XCTUnwrap(engine.result)
        XCTAssertEqual(result.tries, 1)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(result.elapsedMs, 7_000)
        XCTAssertEqual(result.score, Scoring.score(tries: 1, solved: true, elapsedMs: 7_000))
    }

    func testSubmitSolvedOnSecondTry() throws {
        // lockedPuzzle: itemIDs [2,3,1,4,5], correctOrder [1,2,3,4,5].
        var engine = try Fixture.engine(Fixture.lockedPuzzle())
        try engine.move(from: 0, to: 2)
        XCTAssertEqual(engine.currentOrder, [3, 1, 2, 4, 5])
        try engine.submit(elapsedMs: 1_000)
        XCTAssertNil(engine.result)

        // Positions 3,4 (ids 4,5) locked. Rearrange the unlocked sub-list [3,1,2] -> [1,2,3].
        try engine.move(from: 0, to: 2)
        XCTAssertEqual(engine.currentOrder, [1, 2, 3, 4, 5])
        let attempt = try engine.submit(elapsedMs: 2_000)

        XCTAssertTrue(attempt.isSolved)
        XCTAssertEqual(engine.phase, .solved)
        let result = try XCTUnwrap(engine.result)
        XCTAssertEqual(result.tries, 2)
        XCTAssertEqual(result.score, Scoring.score(tries: 2, solved: true, elapsedMs: 2_000))
    }

    func testSubmitSolvedOnThirdTry() throws {
        var engine = try Fixture.engineAfterFirstLockingAttempt(elapsedMs: 1_000)
        XCTAssertNil(engine.result)

        try engine.move(from: 2, to: 0)
        XCTAssertEqual(engine.currentOrder, [2, 3, 1, 4, 5])
        try engine.submit(elapsedMs: 2_000)
        XCTAssertNil(engine.result)

        // Unlocked sub-list [2,3,1] at positions [0,1,2]: remove position 2's value
        // (1), insert it at position 0's rank (index 0) -> [1,2,3].
        try engine.move(from: 2, to: 0)
        XCTAssertEqual(engine.currentOrder, [1, 2, 3, 4, 5])
        let attempt = try engine.submit(elapsedMs: 3_000)

        XCTAssertTrue(attempt.isSolved)
        XCTAssertEqual(engine.phase, .solved)
        let result = try XCTUnwrap(engine.result)
        XCTAssertEqual(result.tries, 3)
        XCTAssertEqual(result.score, Scoring.score(tries: 3, solved: true, elapsedMs: 3_000))
    }

    func testSubmitThreeNonSolvingAttemptsFails() throws {
        let engine = try Fixture.engineAfterThreeFailingAttempts()

        XCTAssertEqual(engine.phase, .failed)
        let result = try XCTUnwrap(engine.result)
        XCTAssertEqual(result.tries, 3)
        XCTAssertFalse(result.solved)
        XCTAssertEqual(result.elapsedMs, 3_000)
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.score, Scoring.score(tries: 3, solved: false, elapsedMs: 3_000))
    }

    func testSubmitAfterSolveThrowsNotPlaying() throws {
        var engine = try Fixture.solvableEngine()
        try engine.submit(elapsedMs: 1_000)
        assertThrows(.notPlaying, try engine.submit(elapsedMs: 2_000))
    }

    func testSubmitAfterThreeFailingAttemptsThrowsNotPlaying() throws {
        var engine = try Fixture.engineAfterThreeFailingAttempts()
        assertThrows(.notPlaying, try engine.submit(elapsedMs: 4_000))
    }

    // MARK: - Bookkeeping

    func testAttemptsAccumulateInSubmissionOrder() throws {
        let engine = try Fixture.engineAfterThreeFailingAttempts()

        XCTAssertEqual(engine.attempts.map(\.elapsedMs), [1_000, 2_000, 3_000])
        XCTAssertEqual(engine.attempts.map(\.order), [
            [3, 1, 2, 4, 5],
            [2, 3, 1, 4, 5],
            [3, 2, 1, 4, 5],
        ])
    }

    func testLockedPositionsEqualsCorrectPositionsOfLastAttempt() throws {
        let engine = try Fixture.engineAfterThreeFailingAttempts()
        let lastAttempt = try XCTUnwrap(engine.attempts.last)

        let lastFeedback = LineupEngine.feedback(for: lastAttempt.order, correctOrder: engine.puzzle.correctOrder)
        let expectedLocked = Set(lastFeedback.indices.filter { lastFeedback[$0] == .correct })

        XCTAssertEqual(engine.lockedPositions, expectedLocked)
        XCTAssertEqual(engine.lockedPositions, [1, 3, 4])
    }
}
