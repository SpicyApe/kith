import XCTest

/// The live end-to-end test from `apps/ios/TESTING.md` §7.
///
/// One test, against the real Supabase project, in this order: sign in with the fixed
/// test phone/OTP → play today's puzzle → check the board and the profile → delete the
/// account, which leaves the backend clean for the next run.
///
/// It is skipped (never failed) when `KITH_TEST_PHONE` / `KITH_TEST_OTP` are absent, so a
/// developer running the `KithLive` scheme locally without secrets gets a skip, and CI
/// only really exercises it in the `live-e2e` job.
///
/// Every wait is 20 s (`KithLiveTestCase.timeout`) because every state change here costs a
/// network round trip; the optional branches use the shorter `optionalTimeout` since their
/// absence is a legitimate outcome. A screenshot is attached at each step.
@MainActor final class KithLiveTests: KithLiveTestCase {

    func testLiveSignInPlayAndDelete() throws {
        guard let phone = testPhone, let otp = testOTP else {
            throw XCTSkip("KITH_TEST_PHONE/KITH_TEST_OTP not set")
        }

        let app = launchLive()

        // MARK: Step 1 — launch and sign in

        // The account may or may not already exist, and a previous run may have left a
        // session behind, so resolve which of the two possible first screens we landed on
        // instead of assuming. Each pass costs at most 4 s, so this settles in ~40 s worst
        // case and returns as soon as either screen is up.
        let phoneField = element("onboarding.phone.field")
        let tabBar = app.tabBars.firstMatch
        var isSignedOut = false
        var launched = false
        for _ in 0..<10 {
            if phoneField.waitForExistence(timeout: 2) {
                isSignedOut = true
                launched = true
                break
            }
            if tabBar.waitForExistence(timeout: 2) {
                launched = true
                break
            }
        }
        step("1. launched")
        XCTAssertTrue(launched,
                      "Step 1: after launch the app reached neither onboarding.phone.field nor the tab bar")

        if isSignedOut {
            typeInto(textField("onboarding.phone.field"), phone,
                     "Step 1: onboarding.phone.field never appeared")
            awaitEnabled(app.buttons["onboarding.phone.continue"], "Step 1: continue button never became enabled")
        awaitAndTap(app.buttons["onboarding.phone.continue"],
                        "Step 1: onboarding.phone.continue never appeared")
            step("1. phone submitted")

            // The six-digit field auto-submits on the last digit, so there is no continue
            // button to tap here — the next screen is what we branch on.
            typeInto(textField("onboarding.code.field"), otp,
                     "Step 1: onboarding.code.field never appeared after sending the code",
                     verify: false)
            step("1. code submitted")

            // New account → name + contacts pre-prompt. Returning account → straight to
            // the tabs, and the name step simply never appears.
            let nameField = app.textFields["onboarding.name.field"]
            if nameField.waitForExistence(timeout: Self.timeout) {
                nameField.tap()
                nameField.typeText("CI Tester")
                awaitEnabled(app.buttons["onboarding.name.continue"], "Step 1: continue button never became enabled")
        awaitAndTap(app.buttons["onboarding.name.continue"],
                            "Step 1: onboarding.name.continue never appeared after typing the name")
                // Saving the name is the first real backend call. Watch briefly for either
                // the contacts prompt or an error toast (toasts fade within seconds, so a
                // plain 20 s wait would miss the reason); re-tap once if nothing changed.
                let notNow = app.buttons["onboarding.contacts.notNow"]
                let deadline = Date().addingTimeInterval(8)
                while Date() < deadline, !notNow.exists {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                }
                if !notNow.exists {
                    // debug.status is a persistent test-only element carrying the model's
                    // stage/step/busy/last-error; reading it is race-free unlike the toast.
                    let status = element("debug.status")
                    if status.exists {
                        XCTFail("Step 1: saving the name did not advance; app status: \(status.label)")
                    }
                    step("1. retrying Continue on the name step")
                    app.buttons["onboarding.name.continue"].tap()
                }
                awaitAndTap(notNow,
                            "Step 1: onboarding.contacts.notNow never appeared after saving the name")
                step("1. registered as a new user")
            } else {
                step("1. signed in as a returning user")
            }
        }

        // MARK: Step 2 — play today's puzzle

        // The Today tab is the games hub now (docs/07); Lineup is the first row on it.
        openHubRow("lineup", "Step 2: hub.row.lineup never appeared on the Today tab")

        // Same two-way branch as step 1: today is either playable or already done. The
        // played card is checked first so it wins if both are momentarily on screen.
        let playedCard = element("today.playedCard")
        let prompt = element("today.prompt")
        var alreadyPlayed = false
        var todayLoaded = false
        for _ in 0..<10 {
            if playedCard.waitForExistence(timeout: 2) {
                alreadyPlayed = true
                todayLoaded = true
                break
            }
            if prompt.waitForExistence(timeout: 2) {
                todayLoaded = true
                break
            }
        }
        step("2. today")
        XCTAssertTrue(todayLoaded,
                      "Step 2: Today showed neither today.prompt nor today.playedCard after signing in")

        if !alreadyPlayed {
            let headline = element("results.headline")
            let lockIn = app.buttons["today.lockIn"]
            var reachedResults = false

            // At most three rounds, because the puzzle allows three tries. Any move makes
            // `today.lockIn` submittable; we do not care whether the order is right, only
            // that the run ends on the results screen (solved or failed both do).
            for round in 1...3 {
                var movedTile: Int?
                for index in 0...3 {
                    let down = app.buttons["today.tile.\(index).down"]
                    if down.exists && down.isEnabled {
                        down.tap()
                        movedTile = index
                        break
                    }
                }
                XCTAssertNotNil(movedTile,
                                "Step 2 (round \(round)): none of today.tile.0.down … today.tile.3.down was present and enabled — are the -uiTestingControls move buttons rendering?")

                // A tap that lands while the pushed screen is still settling can be dropped
                // (the hermetic suite masks this with test iterations; this one has none), so
                // re-tap once if the order did not change within a few seconds.
                let enabled = NSPredicate(format: "isEnabled == true")
                let firstTry = XCTNSPredicateExpectation(predicate: enabled, object: lockIn)
                if XCTWaiter().wait(for: [firstTry], timeout: 5) != .completed, let movedTile {
                    step("2. round \(round): re-tapping tile \(movedTile) down")
                    app.buttons["today.tile.\(movedTile).down"].tap()
                }
                awaitEnabled(lockIn,
                             "Step 2 (round \(round)): today.lockIn never became enabled after moving tile \(movedTile ?? -1) down; app status: \(element("debug.status").exists ? element("debug.status").label : "n/a")")
                lockIn.tap()
                step("2. round \(round) locked in")

                if headline.waitForExistence(timeout: Self.timeout) {
                    reachedResults = true
                    break
                }
            }
            XCTAssertTrue(reachedResults,
                          "Step 2: results.headline never appeared after three lock-ins")

            // MARK: Step 3 — results, then the onboarding tail

            step("3. results")
            awaitElement(element("results.score"),
                         "Step 3: results.score never appeared on the results screen")

            // The results screen is a full-screen cover; it has to be closed before the tab
            // bar is reachable again. Its "Done" button carries the accessibility label
            // "Close results" (it has no identifier in TESTING.md §3), so try both spellings
            // and treat a miss as harmless — a failure here would surface as step 4 anyway.
            if !tapIfPresent(app.buttons["Close results"]) {
                _ = tapIfPresent(app.buttons["Done"])
            }

            // Only a brand-new account sees the tail (friends found → notifications). Both
            // are optional: a 5 s look, and no failure if absent.
            _ = tapIfPresent(app.buttons["onboarding.friends.seeBoard"])
            _ = tapIfPresent(app.buttons["onboarding.notifications.no"])
            step("3. results dismissed")
        }

        // MARK: Step 3b — a grid game: open Stars from the hub and give up

        // Solving a real 8×8 Stars blind is not feasible in a test, so this exercises the
        // start → give up → submit-game → results path instead (PLAN-games.md §"Tests").
        popToHub()
        let starsRow = element("hub.row.stars")
        // `waitForExistence && isEnabled` reads `isEnabled` once, immediately after the
        // existence check returns — before `dailyGames` has necessarily landed and enabled
        // the row — so this step almost always self-skipped (finding B3). Polling the
        // predicate instead waits out that window the same way `awaitEnabled` does
        // elsewhere, but without failing the test when the row never enables (Stars may
        // simply already be played).
        let starsEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: starsRow
        )
        if XCTWaiter().wait(for: [starsEnabled], timeout: Self.timeout) == .completed {
            starsRow.tap()
            step("3b. Stars opened")

            let giveUp = app.buttons["game.giveUp"]
            let giveUpEnabled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isEnabled == true"), object: giveUp
            )
            if XCTWaiter().wait(for: [giveUpEnabled], timeout: Self.timeout) == .completed {
                giveUp.tap()
                // The destructive button of a `confirmationDialog` does not always surface
                // its identifier; its title is unique on screen either way.
                if !tapIfPresent(element("game.giveUp.confirm"), within: Self.optionalTimeout) {
                    awaitAndTap(app.buttons["Give up"],
                                "Step 3b: the give-up confirmation never appeared")
                }
                step("3b. gave up")

                assertLabelContains(element("gameResults.headline"), "Gave up",
                                    "Step 3b: the Stars results headline should read \"Gave up\"")
                awaitElement(element("gameResults.score"),
                             "Step 3b: gameResults.score never appeared")

                if !tapIfPresent(app.buttons["Close results"]) {
                    _ = tapIfPresent(app.buttons["Done"])
                }
                step("3b. Stars results dismissed")
            } else {
                // Stars was already played today (a re-run before the account was deleted):
                // the host screen shows the stored result instead of a playable grid.
                step("3b. Stars already played — skipped")
            }
        } else {
            step("3b. Stars not available today — skipped")
        }

        // MARK: Step 4 — the board

        tapTab("tab.board", "Step 4: tab.board never appeared")
        awaitElement(element("board.header"), "Step 4: board.header never appeared")
        step("4. board")

        // The viewer's own row is `board.row.<my id>`, and we do not know the live id — but
        // it is the only row labelled "You". Match on the identifier prefix as well so the
        // "You" tab-bar item cannot satisfy this.
        let myRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                  "board.row.", "You"))
            .firstMatch
        if !myRow.waitForExistence(timeout: Self.timeout) {
            XCTAssertTrue(app.staticTexts["You"].waitForExistence(timeout: Self.timeout),
                          "Step 4: no board row labelled \"You\" was found on the friends board")
        }

        // MARK: Step 5 — the profile

        tapTab("tab.you", "Step 5: tab.you never appeared")
        let streak = awaitElement(element("profile.streak"),
                                  "Step 5: profile.streak never appeared")
        step("5. profile")
        XCTAssertNotNil(streak.label.rangeOfCharacter(from: .decimalDigits),
                        "Step 5: profile.streak should contain a digit but its label was \"\(streak.label)\"")
        awaitElement(element("profile.inviteCode"),
                     "Step 5: profile.inviteCode never appeared")

        // MARK: Step 6 — delete the account

        // It sits at the very bottom of a lazily rendered profile list, so it may not even
        // exist in the accessibility tree until scrolled into view: swipe first, then wait.
        let deleteAccount = element("profile.deleteAccount")
        for _ in 0..<6 where !deleteAccount.exists {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        awaitElement(deleteAccount, "Step 6: profile.deleteAccount never appeared after scrolling")
        for _ in 0..<3 where !deleteAccount.isHittable {
            app.swipeUp()
        }
        deleteAccount.tap()
        step("6. delete requested")

        // The confirmation is a `confirmationDialog`, whose destructive button carries the
        // `profile.deleteConfirm` identifier; fall back to its title if the action sheet
        // does not surface the identifier.
        let confirm = element("profile.deleteConfirm")
        if confirm.waitForExistence(timeout: Self.timeout) {
            confirm.tap()
        } else {
            awaitAndTap(app.buttons["Delete everything"],
                        "Step 6: profile.deleteConfirm never appeared in the delete confirmation")
        }

        awaitElement(element("onboarding.phone.field"),
                     "Step 6: the app never returned to onboarding.phone.field after deleting the account")
        step("6. deleted and signed out")
    }
}
