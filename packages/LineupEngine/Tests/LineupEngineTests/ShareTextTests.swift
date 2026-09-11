// ShareText.render(result:puzzleNumber:streak:refCode:)

import XCTest
@testable import LineupEngine

final class ShareTextTests: XCTestCase {

    private func attempt(_ feedback: [TileFeedback], elapsedMs: Int = 0) -> Attempt {
        Attempt(order: Array(1...feedback.count), feedback: feedback, elapsedMs: elapsedMs)
    }

    private func result(
        tries: Int,
        solved: Bool,
        elapsedMs: Int,
        attempts: [Attempt]
    ) -> PuzzleResult {
        PuzzleResult(
            puzzleDate: "2026-09-11",
            tries: tries,
            solved: solved,
            elapsedMs: elapsedMs,
            score: Scoring.score(tries: tries, solved: solved, elapsedMs: elapsedMs),
            attempts: attempts
        )
    }

    func testCanonicalExample() {
        // The exact block from the LineupEngine.swift doc comment.
        let puzzleResult = result(
            tries: 2,
            solved: true,
            elapsedMs: 48_210,
            attempts: [
                attempt([.wrong, .near, .correct, .wrong, .near]),
                attempt([.correct, .correct, .correct, .correct, .correct]),
            ]
        )

        let text = ShareText.render(result: puzzleResult, puzzleNumber: 142, streak: 12, refCode: "7F3Q")

        XCTAssertEqual(text, """
        Kith #142 · 2/3 · 0:48 🔥12
        ⬜🟨🟩⬜🟨
        🟩🟩🟩🟩🟩
        kith.app/p/142?r=7F3Q
        """)
    }

    func testNoTrailingNewline() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 0, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 1, streak: 0, refCode: nil)
        XCTAssertFalse(text.hasSuffix("\n"))
    }

    func testShowsXOverThreeWhenNotSolved() {
        let puzzleResult = result(tries: 3, solved: false, elapsedMs: 65_000, attempts: [
            attempt([.wrong, .near, .wrong, .near, .wrong]),
            attempt([.wrong, .near, .wrong, .near, .wrong]),
            attempt([.wrong, .near, .wrong, .near, .wrong]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 7, streak: 5, refCode: nil)
        XCTAssertTrue(text.hasPrefix("Kith #7 · X/3 · 1:05 🔥5\n"))
    }

    func testNoFlameWhenStreakIsZero() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 10_000, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 9, streak: 0, refCode: nil)
        XCTAssertTrue(text.hasPrefix("Kith #9 · 1/3 · 0:10\n"))
        XCTAssertFalse(text.contains("🔥"))
    }

    func testFlameShownWhenStreakIsOne() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 0, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 1, streak: 1, refCode: nil)
        XCTAssertTrue(text.hasPrefix("Kith #1 · 1/3 · 0:00 🔥1\n"))
    }

    func testNoRefCodeQueryWhenNil() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 0, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 55, streak: 0, refCode: nil)
        XCTAssertTrue(text.hasSuffix("kith.app/p/55"))
        XCTAssertFalse(text.contains("?r="))
    }

    func testNoRefCodeQueryWhenEmptyString() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 0, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 55, streak: 0, refCode: "")
        XCTAssertTrue(text.hasSuffix("kith.app/p/55"))
        XCTAssertFalse(text.contains("?r="))
    }

    func testRefCodeQueryWhenPresent() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 0, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 55, streak: 0, refCode: "AB12")
        XCTAssertTrue(text.hasSuffix("kith.app/p/55?r=AB12"))
    }

    // MARK: - m:ss time formatting

    func testTimeFormatting_0_05() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 5_000, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 1, streak: 0, refCode: nil)
        XCTAssertTrue(text.hasPrefix("Kith #1 · 1/3 · 0:05\n"))
    }

    func testTimeFormatting_1_02() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 62_000, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 1, streak: 0, refCode: nil)
        XCTAssertTrue(text.hasPrefix("Kith #1 · 1/3 · 1:02\n"))
    }

    func testTimeFormatting_12_00() {
        let puzzleResult = result(tries: 1, solved: true, elapsedMs: 720_000, attempts: [
            attempt([.correct, .correct, .correct, .correct, .correct]),
        ])
        let text = ShareText.render(result: puzzleResult, puzzleNumber: 1, streak: 0, refCode: nil)
        XCTAssertTrue(text.hasPrefix("Kith #1 · 1/3 · 12:00\n"))
    }
}
