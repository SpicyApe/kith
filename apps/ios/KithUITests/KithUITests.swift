import XCTest

/// The seven UI tests from `apps/ios/TESTING.md` §5.
///
/// Every test launches the app fresh with `-uiTesting -uiTestingState <state>` so the
/// fake backend (TESTING.md §2) and its temporary `FileStore` start clean; the tests are
/// therefore independent and order-insensitive. Identifiers come from TESTING.md §3 and
/// copy from `docs/03-wireframes.md`.
@MainActor final class KithUITests: KithUITestCase {

    // MARK: - 1. Onboarding through to the first puzzle

    /// TESTING.md §5.1 (`fresh`): phone → code → name → "Not now" on contacts →
    /// today's puzzle, with `today.lockIn` disabled until a tile moves.
    func testOnboardingToFirstPuzzle() {
        let app = launch(state: "fresh")

        // 1a. Phone. The fake auth accepts any number; `verify` is the gate.
        typeInto(textField("onboarding.phone.field"), "+15551234567")
        awaitAndTap(app.buttons["onboarding.phone.continue"])

        // 1b. Code. Only `123456` verifies (FakeAuth). The six-digit field auto-submits
        // on the last digit, so the name step is what we wait for next.
        typeInto(textField("onboarding.code.field"), "123456")

        // 1c. Name.
        typeInto(textField("onboarding.name.field"), "Alex")
        awaitAndTap(app.buttons["onboarding.name.continue"])

        // 1d. Contacts pre-prompt — decline so the OS permission sheet never appears.
        awaitAndTap(app.buttons["onboarding.contacts.notNow"])

        // 1e. Straight into today's puzzle.
        awaitElement(element("today.prompt"), "Today's prompt never appeared")
        for index in 0...4 {
            awaitElement(element("today.tile.\(index)"), "today.tile.\(index) never appeared")
        }

        // Lock in is disabled until the user has moved at least one tile.
        let lockIn = awaitElement(app.buttons["today.lockIn"])
        XCTAssertFalse(lockIn.isEnabled, "today.lockIn should be disabled before any move")

        awaitAndTap(app.buttons["today.tile.0.down"])
        awaitEnabled(lockIn, "today.lockIn should be enabled once a tile has moved")
    }

    // MARK: - 2. Solving on the first try

    /// TESTING.md §5.2 (`returning`): the fake presents `[2,1,3,4,5]`, one swap from the
    /// correct `[1,2,3,4,5]`, so moving tile 0 (Telephone) down once solves it.
    func testSolveInOneTry() {
        let app = launch(state: "returning")

        awaitElement(element("today.prompt"), "Today's prompt never appeared")

        let lockIn = awaitElement(app.buttons["today.lockIn"])
        XCTAssertFalse(lockIn.isEnabled, "today.lockIn should be disabled before any move")

        awaitAndTap(app.buttons["today.tile.0.down"])
        awaitEnabled(lockIn, "today.lockIn should be enabled once a tile has moved")
        lockIn.tap()

        assertLabelEquals(element("results.headline"), "Solved in 1")
        awaitElement(element("results.share"), "results.share never appeared")
        awaitElement(element("results.rankTeaser"), "results.rankTeaser never appeared")
    }

    // MARK: - 3. Friends board

    /// TESTING.md §5.3 (`played`): Mum, Sam and Dev have played; the header counts
    /// 3 of 4 friends; the viewer's own row is labelled "You".
    func testBoardShowsFriends() {
        launch(state: "played")

        tapTab("tab.board")

        awaitElement(element("board.row.u-mum"), "board.row.u-mum never appeared")
        awaitElement(element("board.row.u-sam"), "board.row.u-sam never appeared")
        awaitElement(element("board.row.u-dev"), "board.row.u-dev never appeared")

        assertLabelEquals(element("board.header"), "3 of 4 friends played today")

        // The viewer's own row. It carries the `board.row.<userId>` identifier for `u-me`
        // (TESTING.md §2: "Me" is `u-me`) and is labelled "You" rather than the display
        // name; fall back to matching the label alone if the row identifier is absent.
        let myRow = element("board.row.u-me")
        if myRow.waitForExistence(timeout: KithUITestCase.timeout) {
            XCTAssertTrue(myRow.label.contains("You"),
                          "Own board row should be labelled \"You\" but was \"\(myRow.label)\"")
        } else {
            XCTAssertTrue(app.staticTexts["You"].waitForExistence(timeout: KithUITestCase.timeout),
                          "No board row labelled \"You\" was found")
        }
    }

    // MARK: - 4. Already played today

    /// TESTING.md §5.4 (`played`): the Today tab shows the compact results card and the
    /// countdown to the next puzzle instead of a playable board.
    func testAlreadyPlayedShowsCountdown() {
        launch(state: "played")

        awaitElement(element("today.playedCard"), "today.playedCard never appeared")
        awaitElement(element("today.countdown"), "today.countdown never appeared")
    }

    // MARK: - 5. Joining a circle by code

    /// TESTING.md §5.5 (`returning`): the fake accepts both `KITH-ABC123` and `ABC123`
    /// and adds the `Family` chip, whose identifier uses the bare code.
    func testJoinCircleByCode() {
        let app = launch(state: "returning")

        tapTab("tab.circles")

        awaitAndTap(app.buttons["circles.join"])
        typeInto(textField("circles.join.field"), "KITH-ABC123")
        awaitAndTap(app.buttons["circles.join.submit"])

        awaitElement(element("circles.chip.ABC123"), "circles.chip.ABC123 never appeared")
    }

    // MARK: - 6. Profile streak and invite code

    /// TESTING.md §5.6 (`played`): streak is 12 and the invite code is `KITH7F3Q`
    /// (the label may format it as `KITH-7F3Q`, so only the digits/letters are asserted
    /// via `contains` on the raw code).
    func testProfileShowsStreak() {
        launch(state: "played")

        tapTab("tab.you")

        assertLabelContains(element("profile.streak"), "12")
        assertLabelContains(element("profile.inviteCode"), "KITH7F3Q")
    }

    // MARK: - 7. Everyone board disables the period picker

    /// TESTING.md §5.7 (`played`): the Everyone board is today-only, so selecting it in
    /// `board.kind` disables the `board.period` picker.
    func testEveryoneBoardDisablesPeriod() {
        let app = launch(state: "played")

        tapTab("tab.board")

        let kind = awaitElement(app.segmentedControls["board.kind"], "board.kind never appeared")
        awaitAndTap(kind.buttons["Everyone"], "The Everyone segment never appeared")

        let period = app.segmentedControls["board.period"]
        awaitDisabled(period, "board.period should be disabled while the Everyone board is shown")
    }
}
