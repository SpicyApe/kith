// SocialAndProfileTests.swift — TESTING.md §4 tests 7, 10, 11 and 13.

import Foundation
import KithCore
import LineupEngine
import XCTest
@testable import Kith

@MainActor
final class SocialAndProfileTests: XCTestCase {

    /// §4.7. One reaction per person per day: swapping the emoji has to delete the old
    /// row first, or the server counts the merge-upsert as a brand new reaction and
    /// re-notifies. The `played` state seeds my 🔥 on Sam.
    func testReactSwapUnreactsFirst() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        XCTAssertTrue(
            model.reactions.contains { $0.from_user == "u-me" && $0.to_user == "u-sam" },
            "expected a seeded reaction from me to Sam"
        )

        await model.react(to: "u-sam", emoji: "😂")

        let calls = harness.api.calls
        let unreactIndex = try XCTUnwrap(calls.firstIndex(of: "unreact(u-sam)"))
        let reactIndex = try XCTUnwrap(calls.firstIndex(of: "react(u-sam,😂)"))
        XCTAssertLessThan(unreactIndex, reactIndex)
        XCTAssertEqual(
            model.reactions.first { $0.from_user == "u-me" && $0.to_user == "u-sam" }?.emoji,
            "😂"
        )
    }

    /// §4.10
    func testDiscoverableToggleUpdatesProfile() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        await model.updateProfile(ProfilePatch(discoverable: false))

        XCTAssertTrue(
            harness.api.calls.contains("updateProfile(discoverable:false)"),
            "calls were: \(harness.api.calls)"
        )
        XCTAssertEqual(model.profile?.discoverable, false)
    }

    /// §4.11
    func testDeleteAccountResetsState() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        await model.deleteAccount()

        XCTAssertEqual(model.stage, .signedOut)
        XCTAssertNil(model.engine)
        XCTAssertNil(model.profile)
        XCTAssertEqual(model.myUserId, "")
        XCTAssertTrue(model.boards.isEmpty)

        let signedInUser = await harness.auth.currentUserId()
        XCTAssertNil(signedInUser)
        let token = try await harness.auth.accessToken()
        XCTAssertNil(token)
    }

    /// §4.13. `taunts` is write-once per day, and the model closes the field rather than
    /// letting a second insert reach the server at all.
    func testTauntIsWriteOnce() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model

        await harness.boot()
        model.tauntDraft = "gg"
        await model.saveTaunt()
        XCTAssertTrue(model.tauntSaved)
        XCTAssertEqual(harness.callCount("setTaunt"), 1)

        model.tauntDraft = "gg again"
        await model.saveTaunt()

        XCTAssertTrue(model.tauntSaved)
        XCTAssertEqual(harness.callCount("setTaunt"), 1)
    }
}
