// Shared fixtures for LineupEngine tests. Not a test case itself.
//
// The move fixtures below are worked out by hand against the documented `move`
// algorithm (see LineupEngine.swift's doc comment) so that the exact resulting
// `currentOrder` at each step is known ahead of time and asserted against.

import XCTest
@testable import LineupEngine

enum Fixture {
    /// A generic valid puzzle. Presentation order `[3,2,5,4,1]` differs from the
    /// correct order `[1,2,3,4,5]` in every position, which is required because
    /// `canSubmit` is false whenever `currentOrder` matches the untouched initial
    /// order.
    static func puzzle(
        date: String = "2026-09-11",
        number: Int = 142,
        prompt: String = "Order these by the year they were invented",
        direction: String = "Earliest at the top",
        itemIDs: [Int] = [3, 2, 5, 4, 1],
        correctOrder: [Int] = [1, 2, 3, 4, 5]
    ) -> Puzzle {
        Puzzle(
            date: date,
            number: number,
            prompt: prompt,
            direction: direction,
            items: itemIDs.map { PuzzleItem(id: $0, label: "Item \($0)") },
            correctOrder: correctOrder
        )
    }

    static func engine(_ puzzle: Puzzle = Fixture.puzzle()) throws -> LineupEngine {
        try LineupEngine(puzzle: puzzle)
    }

    /// Presentation order `[2,1,3,4,5]`: a single adjacent swap away from
    /// `correctOrder [1,2,3,4,5]`, so `move(from: 0, to: 1)` solves it outright.
    static func almostSolvedPuzzle() -> Puzzle {
        puzzle(itemIDs: [2, 1, 3, 4, 5], correctOrder: [1, 2, 3, 4, 5])
    }

    /// Engine whose `currentOrder` equals `correctOrder`, ready to submit a solve.
    static func solvableEngine() throws -> LineupEngine {
        var engine = try LineupEngine(puzzle: almostSolvedPuzzle())
        try engine.move(from: 0, to: 1)
        precondition(engine.currentOrder == [1, 2, 3, 4, 5])
        return engine
    }

    /// Presentation order `[2,3,1,4,5]`, correct order `[1,2,3,4,5]`.
    ///
    /// After `move(from: 0, to: 2)` and `submit`, positions 3 and 4 (ids 4, 5) lock
    /// and stay locked for the rest of the game; positions 0, 1, 2 cycle through the
    /// two derangements of {1,2,3} on the next two attempts so the puzzle never
    /// solves. Used for locked-position and multi-attempt tests.
    static func lockedPuzzle() -> Puzzle {
        puzzle(itemIDs: [2, 3, 1, 4, 5], correctOrder: [1, 2, 3, 4, 5])
    }

    /// Engine after one submission on `lockedPuzzle()`. `currentOrder == [3,1,2,4,5]`,
    /// attempts == 1, locked positions == {3, 4}.
    static func engineAfterFirstLockingAttempt(elapsedMs: Int = 1_000) throws -> LineupEngine {
        var engine = try LineupEngine(puzzle: lockedPuzzle())
        try engine.move(from: 0, to: 2)
        precondition(engine.currentOrder == [3, 1, 2, 4, 5])
        try engine.submit(elapsedMs: elapsedMs)
        return engine
    }

    /// Engine after three submissions on `lockedPuzzle()`, none solving. Final phase
    /// is `.failed`. Attempt orders, in submission order:
    /// `[3,1,2,4,5]`, `[2,3,1,4,5]`, `[3,2,1,4,5]`, with elapsed 1000/2000/3000.
    static func engineAfterThreeFailingAttempts() throws -> LineupEngine {
        var engine = try engineAfterFirstLockingAttempt(elapsedMs: 1_000)

        try engine.move(from: 2, to: 0)
        precondition(engine.currentOrder == [2, 3, 1, 4, 5])
        try engine.submit(elapsedMs: 2_000)

        try engine.move(from: 0, to: 1)
        precondition(engine.currentOrder == [3, 2, 1, 4, 5])
        try engine.submit(elapsedMs: 3_000)

        precondition(engine.phase == .failed)
        return engine
    }
}

func assertInvalidPuzzle(
    _ puzzle: Puzzle,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try LineupEngine(puzzle: puzzle), file: file, line: line) { error in
        guard case LineupError.invalidPuzzle = error else {
            XCTFail("expected LineupError.invalidPuzzle, got \(error)", file: file, line: line)
            return
        }
    }
}

func assertThrows<T>(
    _ expected: LineupError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: @autoclosure () throws -> T
) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        guard let lineupError = error as? LineupError else {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(lineupError, expected, file: file, line: line)
    }
}
