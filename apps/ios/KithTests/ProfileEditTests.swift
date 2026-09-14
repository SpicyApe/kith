// ProfileEditTests.swift — docs/07-games-hub.md §Product rules → "Profile
// (2026-09-13)": renaming and uploading a profile picture through `AppModel`.
// See apps/ios/TESTING.md §4.

import Foundation
import KithCore
import XCTest
@testable import Kith

@MainActor
final class ProfileEditTests: XCTestCase {

    /// `EditProfileView`'s Save button calls this; it should both update the local
    /// `profile.display_name` and record the patch on the fake.
    func testUpdateProfileRenamesDisplayNameAndRecordsCall() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model
        await harness.boot()

        await model.updateProfile(ProfilePatch(display_name: "Alexandra"))

        XCTAssertEqual(model.profile?.display_name, "Alexandra")
        XCTAssertTrue(
            harness.api.calls.contains { $0.hasPrefix("updateProfile(") && $0.contains("display_name:Alexandra") },
            "expected an updateProfile call naming the new display name, got \(harness.api.calls)"
        )
    }

    /// `EditProfileView`'s photo picker calls this after `ImageResizer.squareJPEG`.
    func testUploadAvatarBumpsVersionAndRecordsByteCount() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model
        await harness.boot()

        let before = model.profile?.avatar_version ?? 0
        let jpeg = Data(repeating: 0xFF, count: 1_234)
        await model.uploadAvatar(jpeg: jpeg)

        XCTAssertEqual(model.profile?.avatar_version, before + 1)
        XCTAssertEqual(harness.api.avatarUploadSizes.last, 1_234)
        XCTAssertTrue(harness.callCount("uploadAvatar") > 0)
    }

    /// `SupabaseKithAPI.avatarURL` is a method on the concrete client, not on `KithAPI`;
    /// `AppModel.avatarURL` must stay nil for the fakes so the tests never touch the
    /// network, even once a version is set.
    func testAvatarURLIsNilForTheFake() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model
        await harness.boot()

        await model.uploadAvatar(jpeg: Data(repeating: 1, count: 10))

        XCTAssertNotNil(model.profile?.avatar_version)
        XCTAssertNil(model.avatarURL(userId: model.myUserId, version: model.profile?.avatar_version))
    }

    /// The board's Today/Yesterday toggle (docs/07 "Added later the same day"):
    /// `refreshBoard(date:)` keys the cache by the requested date and passes that date
    /// through to the fake.
    func testRefreshBoardKeysRowsByDateAndPassesDateToFake() async throws {
        let harness = Harness(.played)
        defer { harness.cleanUp() }
        let model = harness.model
        await harness.boot()

        await model.refreshBoard(kind: .friends, scopeId: nil, period: .today,
                                 date: model.yesterday, force: true)

        XCTAssertNotEqual(model.today, model.yesterday)
        let todayKey = BoardCacheKey(kind: .friends, scopeId: nil, period: .today, date: model.today)
        let yesterdayKey = BoardCacheKey(kind: .friends, scopeId: nil, period: .today, date: model.yesterday)
        XCTAssertNotNil(model.boards[todayKey], "bootstrap already loaded today's board")
        XCTAssertNotNil(model.boards[yesterdayKey], "the explicit date: call should have loaded yesterday's board")
        XCTAssertTrue(harness.api.boardDates.contains(model.yesterday),
                      "refreshBoard(date:) should pass the requested date to the fake")
    }
}
