// Shared golden vectors, cross-checked against the Deno test in
// supabase/functions/_shared/lineup_test.ts ("golden vectors"). Both suites read the
// same Fixtures/golden.json so `feedback`, `score`, and `ShareText.render` stay in
// lock-step between the Swift engine and its TypeScript twin.

import XCTest
@testable import LineupEngine

private struct GoldenAttempt: Decodable {
    let order: [Int]
    let elapsedMs: Int
    let feedback: [TileFeedback]
}

private struct GoldenShare: Decodable {
    let puzzleNumber: Int
    let streak: Int
    let refCode: String?
    let text: String
}

private struct GoldenCase: Decodable {
    let name: String
    let correctOrder: [Int]
    let attempts: [GoldenAttempt]
    let tries: Int
    let solved: Bool
    let elapsedMs: Int
    let score: Int
    let share: GoldenShare
}

private struct GoldenFixture: Decodable {
    let cases: [GoldenCase]
}

final class GoldenVectorTests: XCTestCase {

    private func loadFixture() throws -> GoldenFixture {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures"),
            "golden.json not found in test bundle resources"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GoldenFixture.self, from: data)
    }

    func testGoldenVectors() throws {
        let fixture = try loadFixture()
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 6, "expected at least 6 golden cases")

        for goldenCase in fixture.cases {
            for (i, attempt) in goldenCase.attempts.enumerated() {
                let feedback = LineupEngine.feedback(for: attempt.order, correctOrder: goldenCase.correctOrder)
                XCTAssertEqual(
                    feedback, attempt.feedback,
                    "\(goldenCase.name): attempt \(i) feedback mismatch"
                )
            }

            let score = Scoring.score(tries: goldenCase.tries, solved: goldenCase.solved, elapsedMs: goldenCase.elapsedMs)
            XCTAssertEqual(score, goldenCase.score, "\(goldenCase.name): score mismatch")

            let result = PuzzleResult(
                puzzleDate: "2026-09-11",
                tries: goldenCase.tries,
                solved: goldenCase.solved,
                elapsedMs: goldenCase.elapsedMs,
                score: goldenCase.score,
                attempts: goldenCase.attempts.map {
                    Attempt(order: $0.order, feedback: $0.feedback, elapsedMs: $0.elapsedMs)
                }
            )
            let text = ShareText.render(
                result: result,
                puzzleNumber: goldenCase.share.puzzleNumber,
                streak: goldenCase.share.streak,
                refCode: goldenCase.share.refCode
            )
            XCTAssertEqual(text, goldenCase.share.text, "\(goldenCase.name): shareText mismatch")
        }
    }
}
