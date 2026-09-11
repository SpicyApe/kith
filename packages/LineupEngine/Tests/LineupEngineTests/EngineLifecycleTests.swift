// init validation and the state of a freshly-constructed engine.

import XCTest
@testable import LineupEngine

final class EngineLifecycleTests: XCTestCase {

    // MARK: - init validation

    func testWrongItemCountTooFew() {
        let puzzle = Fixture.puzzle(itemIDs: [1, 2, 3, 4])
        assertInvalidPuzzle(puzzle)
    }

    func testWrongItemCountTooMany() {
        let puzzle = Fixture.puzzle(itemIDs: [1, 2, 3, 4, 5, 6])
        assertInvalidPuzzle(puzzle)
    }

    func testDuplicateItemIDs() {
        let puzzle = Fixture.puzzle(itemIDs: [1, 2, 2, 4, 5])
        assertInvalidPuzzle(puzzle)
    }

    func testCorrectOrderWrongLengthTooShort() {
        let puzzle = Fixture.puzzle(correctOrder: [1, 2, 3, 4])
        assertInvalidPuzzle(puzzle)
    }

    func testCorrectOrderWrongLengthTooLong() {
        let puzzle = Fixture.puzzle(correctOrder: [1, 2, 3, 4, 5, 1])
        assertInvalidPuzzle(puzzle)
    }

    func testCorrectOrderNotAPermutationForeignID() {
        // 6 isn't one of the item ids, and 5 is missing.
        let puzzle = Fixture.puzzle(itemIDs: [1, 2, 3, 4, 5], correctOrder: [1, 2, 3, 4, 6])
        assertInvalidPuzzle(puzzle)
    }

    func testCorrectOrderNotAPermutationDuplicate() {
        let puzzle = Fixture.puzzle(itemIDs: [1, 2, 3, 4, 5], correctOrder: [1, 2, 3, 4, 4])
        assertInvalidPuzzle(puzzle)
    }

    func testInitRejectsPresentationOrderEqualToCorrectOrder() {
        let puzzle = Fixture.puzzle(itemIDs: [1, 2, 3, 4, 5], correctOrder: [1, 2, 3, 4, 5])
        assertInvalidPuzzle(puzzle)
    }

    func testBadDateFormatSlashes() {
        let puzzle = Fixture.puzzle(date: "2026/09/11")
        assertInvalidPuzzle(puzzle)
    }

    func testBadDateFormatSingleDigitMonth() {
        let puzzle = Fixture.puzzle(date: "2026-9-11")
        assertInvalidPuzzle(puzzle)
    }

    func testBadDateFormatNotADate() {
        let puzzle = Fixture.puzzle(date: "today")
        assertInvalidPuzzle(puzzle)
    }

    func testBadDateFormatTrailingGarbage() {
        let puzzle = Fixture.puzzle(date: "2026-09-11x")
        assertInvalidPuzzle(puzzle)
    }

    // MARK: - Valid puzzle initial state

    func testValidPuzzleStartsPlaying() throws {
        let engine = try Fixture.engine()
        XCTAssertEqual(engine.phase, .playing)
    }

    func testValidPuzzleInitialCurrentOrderMatchesItems() throws {
        let puzzle = Fixture.puzzle()
        let engine = try Fixture.engine(puzzle)
        XCTAssertEqual(engine.currentOrder, puzzle.items.map(\.id))
    }

    func testValidPuzzleStartsWithNoAttempts() throws {
        let engine = try Fixture.engine()
        XCTAssertTrue(engine.attempts.isEmpty)
    }

    func testValidPuzzleStartsWithThreeTriesRemaining() throws {
        let engine = try Fixture.engine()
        XCTAssertEqual(engine.triesRemaining, 3)
    }

    func testValidPuzzleStartsWithNoLockedPositions() throws {
        let engine = try Fixture.engine()
        XCTAssertTrue(engine.lockedPositions.isEmpty)
    }

    func testValidPuzzleStartsWithCanSubmitFalse() throws {
        let engine = try Fixture.engine()
        XCTAssertFalse(engine.canSubmit)
    }

    func testValidPuzzleStartsWithNoResult() throws {
        let engine = try Fixture.engine()
        XCTAssertNil(engine.result)
    }
}
