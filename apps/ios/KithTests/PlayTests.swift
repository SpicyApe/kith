// PlayTests.swift — TESTING.md §4 tests 4, 6, 8, 9: the engine as `AppModel` drives it.

import Foundation
import KithCore
import LineupEngine
import XCTest
@testable import Kith

@MainActor
final class PlayTests: XCTestCase {

    /// §4.4. Presentation order is [2, 1, 3, 4, 5]; moving tile 0 down one slot makes it
    /// [1, 2, 3, 4, 5], which is the correct order.
    func testSolveOnFirstTrySubmitsAndReveals() async throws {
        let harness = Harness(.returning)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        model.moveRows(from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(model.engine?.currentOrder, [1, 2, 3, 4, 5])

        await model.lockIn()

        let result = try XCTUnwrap(model.localResult)
        XCTAssertEqual(result.tries, 1)
        XCTAssertTrue(result.solved)
        XCTAssertEqual(
            result.score,
            Scoring.score(tries: 1, solved: true, elapsedMs: result.elapsedMs)
        )
        XCTAssertEqual(model.reveal.count, 5)
        XCTAssertFalse(model.resultPendingSync)
        XCTAssertTrue(harness.api.calls.contains("submitResult"))

        let share = try XCTUnwrap(model.resultsSummary?.shareText)
        XCTAssertTrue(share.hasPrefix("Kith #142 · 1/3"), "share text was: \(share)")
    }

    /// §4.6. The server already holds today's result in the `played` state, so a second
    /// submission comes back 409 `already_played` — which `finish` treats as success.
    func testAlreadyPlayedIsTreatedAsSuccess() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        XCTAssertTrue(model.playedToday)
        XCTAssertNil(model.engine)

        // A fresh engine over the same puzzle, as if the round had been started before
        // the server learned about the result.
        let puzzle = try XCTUnwrap(model.puzzle)
        model.engine = try LineupEngine(puzzle: puzzle)
        model.revealedAt = Date()

        model.moveRows(from: IndexSet(integer: 0), to: 2)
        await model.lockIn()

        XCTAssertNotNil(model.localResult)
        XCTAssertFalse(model.resultPendingSync)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.queuedResult)
    }

    /// §4.8. Submitting [1, 3, 4, 2, 5] locks positions 0 and 4; a drop aimed at the
    /// locked bottom row has to slide to the nearest unlocked slot instead.
    func testMoveRowsClampsToUnlocked() async throws {
        let harness = Harness(.returning)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        model.move(from: 0, to: 3)
        XCTAssertEqual(model.engine?.currentOrder, [1, 3, 4, 2, 5])

        await model.lockIn()
        XCTAssertEqual(model.engine?.lockedPositions, Set([0, 4]))
        XCTAssertEqual(model.engine?.phase, .playing)

        model.moveRows(from: IndexSet(integer: 1), to: 4)

        // Item 3 started at position 1 and lands at position 3, the last unlocked slot.
        XCTAssertEqual(model.engine?.currentOrder, [1, 4, 2, 3, 5])
        XCTAssertEqual(model.engine?.currentOrder[3], 3)
    }

    /// §4.9. A reload mid-round (pull to refresh, a returning profile fetch) must not
    /// throw the player's tiles away.
    func testLoadTodayDuringPlayKeepsEngine() async throws {
        let harness = Harness(.returning)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        model.moveRows(from: IndexSet(integer: 0), to: 2)
        let order = try XCTUnwrap(model.engine?.currentOrder)
        let revealedAt = model.revealedAt

        await model.loadToday()

        XCTAssertEqual(model.engine?.currentOrder, order)
        XCTAssertEqual(model.revealedAt, revealedAt)
    }
}
