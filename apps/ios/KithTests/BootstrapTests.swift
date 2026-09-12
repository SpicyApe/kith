// BootstrapTests.swift — TESTING.md §4 tests 1–3: what launch does in each state.

import Foundation
import KithCore
import LineupEngine
import XCTest
@testable import Kith

@MainActor
final class BootstrapTests: XCTestCase {

    /// §4.1
    func testFreshBootstrapIsSignedOut() async throws {
        let harness = Harness(.fresh)
        defer { harness.cleanUp() }

        await harness.boot()

        XCTAssertEqual(harness.model.stage, .signedOut)
        XCTAssertEqual(harness.model.onboarding.step, .phone)
        XCTAssertNil(harness.model.engine)
    }

    /// §4.2
    func testVerifyThenSaveNameLoadsToday() async throws {
        let harness = Harness(.fresh)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()

        model.phoneDraft = "+15551234567"
        await model.sendCode()
        XCTAssertEqual(model.onboarding.step, .code(phone: "+15551234567"))

        model.codeDraft = "123456"
        await model.verifyCode()
        // `fresh` has no `users` row yet, so verifying lands on the name step.
        XCTAssertEqual(model.stage, .registering)
        XCTAssertEqual(model.onboarding.step, .name)

        model.nameDraft = "Alex"
        await model.saveName()

        XCTAssertEqual(model.stage, .ready)
        XCTAssertNotNil(model.engine)
        XCTAssertEqual(model.puzzle?.number, 142)
        XCTAssertEqual(model.engine?.phase, .playing)
    }

    /// §4.3. The fake's friends board is Mum, Sam and Dev (played) plus Jo (not played),
    /// which is the "3 of 4 friends played today" header §5.3 asserts on; my own row
    /// makes five in total.
    func testReturningBootstrapLoadsPuzzleAndBoard() async throws {
        let harness = Harness(.returning)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()

        XCTAssertEqual(model.stage, .ready)
        XCTAssertEqual(model.myUserId, "u-me")
        XCTAssertEqual(model.engine?.phase, .playing)
        XCTAssertEqual(model.puzzle?.number, 142)

        let key = BoardCacheKey(kind: .friends, scopeId: nil, period: .today, date: model.today)
        let cached = try XCTUnwrap(model.boards[key])
        let friends = cached.filter { $0.user_id != model.myUserId }
        XCTAssertEqual(friends.count, 4)
        XCTAssertEqual(friends.filter(\.played).count, 3)
        XCTAssertEqual(
            model.boardHeader(kind: .friends, scopeId: nil, period: .today),
            "3 of 4 friends played today"
        )
        // I have not played in `returning`.
        XCTAssertFalse(model.playedToday)
    }
}
