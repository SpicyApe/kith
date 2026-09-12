// OfflineAndMidnightTests.swift — TESTING.md §4 tests 5 and 14: the two places where
// the app has to recover on its own (a failed submit, and the date changing under it).

import Foundation
import KithCore
import LineupEngine
import XCTest
@testable import Kith

@MainActor
final class OfflineAndMidnightTests: XCTestCase {

    /// §4.5
    func testOfflineSubmitQueuesAndReplays() async throws {
        let harness = Harness(.returning)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        harness.api.failNextSubmit = true

        model.moveRows(from: IndexSet(integer: 0), to: 2)
        await model.lockIn()

        // The result is still the player's, locally, even though the server never saw it.
        XCTAssertNotNil(model.localResult)
        XCTAssertTrue(model.resultPendingSync)
        let toast = try XCTUnwrap(model.toast?.text)
        XCTAssertTrue(toast.lowercased().contains("sync"), "toast was: \(toast)")

        let queued = try XCTUnwrap(model.queuedResult)
        XCTAssertEqual(queued.puzzleDate, model.today)
        let queueFile = harness.directory
            .appendingPathComponent(StoreKey.queuedResult)
            .appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: queueFile.path))
        XCTAssertEqual(harness.callCount("submitResult"), 1)

        await model.onForeground()

        XCTAssertEqual(harness.callCount("submitResult"), 2)
        XCTAssertFalse(model.resultPendingSync)
        XCTAssertNil(model.queuedResult)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queueFile.path))
    }

    /// §4.14
    func testMidnightFlipReloadsPuzzle() async throws {
        let harness = Harness(.returning)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        let startsBefore = harness.callCount("startPuzzle")
        XCTAssertGreaterThan(startsBefore, 0)

        let yesterday = LocalDay.shift(model.today, by: -1)
        model.today = yesterday
        XCTAssertEqual(model.today, yesterday)

        await model.applyMidnight()

        XCTAssertEqual(model.today, LocalDay.date(Date(), tz: model.tz))
        XCTAssertGreaterThan(harness.callCount("startPuzzle"), startsBefore)
        XCTAssertEqual(model.puzzle?.date, model.today)
        XCTAssertEqual(model.engine?.phase, .playing)
    }
}
