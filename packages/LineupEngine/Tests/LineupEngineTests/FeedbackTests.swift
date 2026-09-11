// LineupEngine.feedback(for:correctOrder:) — the pure per-position comparison.

import XCTest
@testable import LineupEngine

final class FeedbackTests: XCTestCase {
    private let correctOrder = [1, 2, 3, 4, 5]

    func testAllCorrect() {
        let feedback = LineupEngine.feedback(for: [1, 2, 3, 4, 5], correctOrder: correctOrder)
        XCTAssertEqual(feedback, [.correct, .correct, .correct, .correct, .correct])
    }

    func testAllWrong() {
        // Rotate left by 2: every id's correct index is 2 or 3 away from where it sits.
        let feedback = LineupEngine.feedback(for: [3, 4, 5, 1, 2], correctOrder: correctOrder)
        XCTAssertEqual(feedback, [.wrong, .wrong, .wrong, .wrong, .wrong])
    }

    func testNearMissInteriorAboveAndBelow() {
        // Swap positions 1 and 2 (non-edge). Position 1 now holds an id whose correct
        // spot is one below (near, "above" its slot); position 2 holds one whose
        // correct spot is one above (near, "below" its slot). Positions 0, 3, 4 stay
        // correct, showing correct tiles adjacent to near ones are still `.correct`.
        let feedback = LineupEngine.feedback(for: [1, 3, 2, 4, 5], correctOrder: correctOrder)
        XCTAssertEqual(feedback, [.correct, .near, .near, .correct, .correct])
    }

    func testNearMissAtEdgePositionZero() {
        // Swap positions 0 and 1.
        let feedback = LineupEngine.feedback(for: [2, 1, 3, 4, 5], correctOrder: correctOrder)
        XCTAssertEqual(feedback[0], .near)
        XCTAssertEqual(feedback, [.near, .near, .correct, .correct, .correct])
    }

    func testNearMissAtEdgePositionFour() {
        // Swap positions 3 and 4.
        let feedback = LineupEngine.feedback(for: [1, 2, 3, 5, 4], correctOrder: correctOrder)
        XCTAssertEqual(feedback[4], .near)
        XCTAssertEqual(feedback, [.correct, .correct, .correct, .near, .near])
    }

    func testWrongWhenTwoAway() {
        // Correct index of 4 relative to position 1 is 2 away: neither correct nor near.
        let feedback = LineupEngine.feedback(for: [1, 4, 3, 2, 5], correctOrder: correctOrder)
        XCTAssertEqual(feedback, [.correct, .wrong, .correct, .wrong, .correct])
    }
}
