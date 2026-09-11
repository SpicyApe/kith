// Codable round-tripping for the wire types shared with the server.

import XCTest
@testable import LineupEngine

final class CodableTests: XCTestCase {

    func testAttemptRoundTripsThroughJSON() throws {
        let attempt = Attempt(
            order: [5, 4, 3, 2, 1],
            feedback: [.correct, .near, .wrong, .correct, .near],
            elapsedMs: 12_345
        )

        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(Attempt.self, from: data)

        XCTAssertEqual(decoded, attempt)
    }

    func testAttemptFeedbackRawValuesAreLowercaseWords() throws {
        let attempt = Attempt(
            order: [1, 2, 3, 4, 5],
            feedback: [.correct, .near, .wrong, .correct, .near],
            elapsedMs: 0
        )

        let data = try JSONEncoder().encode(attempt)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let feedback = try XCTUnwrap(json["feedback"] as? [String])

        XCTAssertEqual(feedback, ["correct", "near", "wrong", "correct", "near"])
    }

    func testPuzzleRoundTripsThroughJSON() throws {
        let puzzle = Puzzle(
            date: "2026-09-11",
            number: 142,
            prompt: "Order these by the year they were invented",
            direction: "Earliest at the top",
            items: [
                PuzzleItem(id: 3, label: "Telephone"),
                PuzzleItem(id: 2, label: "Radio"),
                PuzzleItem(id: 5, label: "Television"),
                PuzzleItem(id: 4, label: "Automobile"),
                PuzzleItem(id: 1, label: "Photograph"),
            ],
            correctOrder: [1, 2, 3, 4, 5]
        )

        let data = try JSONEncoder().encode(puzzle)
        let decoded = try JSONDecoder().decode(Puzzle.self, from: data)

        XCTAssertEqual(decoded, puzzle)
    }

    func testPuzzleResultRoundTripsThroughJSON() throws {
        let result = PuzzleResult(
            puzzleDate: "2026-09-11",
            tries: 2,
            solved: true,
            elapsedMs: 48_210,
            score: 904,
            attempts: [
                Attempt(order: [1, 2, 4, 3, 5], feedback: [.correct, .correct, .near, .near, .correct], elapsedMs: 10_000),
                Attempt(order: [1, 2, 3, 4, 5], feedback: [.correct, .correct, .correct, .correct, .correct], elapsedMs: 48_210),
            ]
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PuzzleResult.self, from: data)

        XCTAssertEqual(decoded, result)
    }

    func testTileFeedbackDecodesFromServerStrings() throws {
        let json = """
        {"order":[1,2,3,4,5],"feedback":["correct","near","wrong","correct","near"],"elapsedMs":1}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let attempt = try JSONDecoder().decode(Attempt.self, from: data)

        XCTAssertEqual(attempt.order, [1, 2, 3, 4, 5])
        XCTAssertEqual(attempt.feedback, [.correct, .near, .wrong, .correct, .near])
        XCTAssertEqual(attempt.elapsedMs, 1)
    }
}
