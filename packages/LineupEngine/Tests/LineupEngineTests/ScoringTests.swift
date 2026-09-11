// Scoring.score(tries:solved:elapsedMs:)

import XCTest
@testable import LineupEngine

final class ScoringTests: XCTestCase {

    // MARK: - Base points at zero elapsed time

    func testSolvedTry1AtZeroElapsed() {
        XCTAssertEqual(Scoring.score(tries: 1, solved: true, elapsedMs: 0), 1000)
    }

    func testSolvedTry2AtZeroElapsed() {
        XCTAssertEqual(Scoring.score(tries: 2, solved: true, elapsedMs: 0), 700)
    }

    func testSolvedTry3AtZeroElapsed() {
        XCTAssertEqual(Scoring.score(tries: 3, solved: true, elapsedMs: 0), 400)
    }

    // MARK: - Time penalty: 2 points per whole elapsed second

    func testPenaltyAt1500Ms() {
        // floor(1500/1000) = 1 whole second -> penalty 2.
        XCTAssertEqual(Scoring.score(tries: 1, solved: true, elapsedMs: 1_500), 1000 - 2)
    }

    func testPenaltyAt48210Ms() {
        // floor(48210/1000) = 48 whole seconds -> penalty 96.
        XCTAssertEqual(Scoring.score(tries: 1, solved: true, elapsedMs: 48_210), 1000 - 96)
    }

    // MARK: - Penalty cap at 240

    func testPenaltyCapsAt200_000Ms() {
        // floor(200000/1000) = 200s, min(200,120) = 120 -> penalty 240.
        XCTAssertEqual(Scoring.score(tries: 1, solved: true, elapsedMs: 200_000), 1000 - 240)
    }

    func testPenaltyCapAppliesJustPast120Seconds() {
        XCTAssertEqual(Scoring.score(tries: 2, solved: true, elapsedMs: 121_000), 700 - 240)
    }

    func testPenaltyAtExactly120Seconds() {
        XCTAssertEqual(Scoring.score(tries: 1, solved: true, elapsedMs: 120_000), 1000 - 240)
        XCTAssertEqual(Scoring.score(tries: 1, solved: true, elapsedMs: 119_999), 1000 - 238)
    }

    // MARK: - Not solved is always a flat 100

    func testNotSolvedIsFlat100RegardlessOfTime() {
        XCTAssertEqual(Scoring.score(tries: 1, solved: false, elapsedMs: 0), 100)
        XCTAssertEqual(Scoring.score(tries: 3, solved: false, elapsedMs: 500_000), 100)
    }

    // MARK: - tries clamped to 1...3

    func testTriesZeroClampedToOne() {
        XCTAssertEqual(
            Scoring.score(tries: 0, solved: true, elapsedMs: 0),
            Scoring.score(tries: 1, solved: true, elapsedMs: 0)
        )
    }

    func testTriesSevenClampedToThree() {
        XCTAssertEqual(
            Scoring.score(tries: 7, solved: true, elapsedMs: 0),
            Scoring.score(tries: 3, solved: true, elapsedMs: 0)
        )
    }

    func testNegativeTriesClampedToOne() {
        XCTAssertEqual(
            Scoring.score(tries: -5, solved: true, elapsedMs: 0),
            Scoring.score(tries: 1, solved: true, elapsedMs: 0)
        )
    }

    // MARK: - Negative elapsed treated as zero

    func testNegativeElapsedTreatedAsZero() {
        XCTAssertEqual(
            Scoring.score(tries: 1, solved: true, elapsedMs: -500),
            Scoring.score(tries: 1, solved: true, elapsedMs: 0)
        )
    }
}
