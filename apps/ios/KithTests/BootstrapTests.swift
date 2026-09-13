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
    /// A number typed the way people write them — "(571) 341-0690", "571.341.0690",
    /// "1 571 341 0690" — is sent to Supabase as E.164, and the same E.164 string is used
    /// for verify. Garbage is refused before any network call.
    func testSendCodeNormalisesFormattedNumbers() async throws {
        let harness = Harness(.fresh)
        defer { harness.cleanUp() }
        let model = harness.model
        await harness.boot()

        for raw in ["(571) 341-0690", "571.341.0690", "1 571 341 0690", "+1 (571) 341-0690"] {
            model.phoneDraft = raw
            await model.sendCode()
            XCTAssertEqual(model.phoneE164, "+15713410690", "for \(raw)")
            XCTAssertEqual(model.onboarding.step, .code(phone: "+15713410690"), "for \(raw)")
            XCTAssertEqual(harness.auth.calls.last, "sendCode(+15713410690)", "for \(raw)")
        }

        XCTAssertEqual(AppModel.normalizedPhone("(571) 341-0690", region: "US"), "+15713410690")
        XCTAssertEqual(AppModel.normalizedPhone("020 7946 0958", region: "GB"), "+442079460958")
        XCTAssertNil(AppModel.normalizedPhone("hello", region: "US"))
        XCTAssertNil(AppModel.normalizedPhone("12345", region: "US"))

        let callsBefore = harness.auth.calls.count
        model.phoneDraft = "call me"
        await model.sendCode()
        XCTAssertEqual(harness.auth.calls.count, callsBefore, "garbage must not reach sendCode")
    }

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
