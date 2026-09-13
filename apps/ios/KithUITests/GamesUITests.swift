import XCTest

/// The hermetic games-hub UI tests from `apps/ios/PLAN-games.md` §"Tests".
///
/// They rely on the tiny deterministic puzzles `FakeKithAPI` serves under `-uiTesting`
/// (TESTING.md §3, "Games hub"): Stars 5×5 solved by the columns `[1, 3, 0, 2, 4]`, Duo 6×6
/// with six blanks, Trail 3×3 with a forced snake.
@MainActor final class GamesUITests: KithUITestCase {

    /// The Stars solution, as (row, column) pairs. Each cell needs two taps: the cycle is
    /// empty → ✕ → ★.
    private static let starCells = [(0, 1), (1, 3), (2, 0), (3, 2), (4, 4)]

    // MARK: - 1. The hub lists four games

    func testHubListsFourGames() {
        launch(state: "returning")

        awaitElement(element("hub.row.lineup"), "hub.row.lineup never appeared",
                     timeout: KithUITestCase.launchTimeout)
        awaitElement(element("hub.row.stars"), "hub.row.stars never appeared")
        awaitElement(element("hub.row.duo"), "hub.row.duo never appeared")
        awaitElement(element("hub.row.trail"), "hub.row.trail never appeared")
        awaitElement(element("hub.row.quint"), "hub.row.quint never appeared")

        assertLabelContains(element("hub.streak"), "12")
        awaitElement(element("hub.countdown"), "hub.countdown never appeared")

        // Lineup still opens the original play screen.
        openHubRow("lineup")
        awaitElement(element("today.prompt"), "Lineup's prompt never appeared from the hub")
    }

    // MARK: - 2. Solving the fake Stars puzzle

    func testSolveFakeStars() {
        let app = launch(state: "returning")

        openHubRow("stars")
        awaitElement(element("game.timer"), "game.timer never appeared on the Stars screen",
                     timeout: KithUITestCase.launchTimeout)

        for (row, column) in Self.starCells {
            tapCell("stars.cell.\(row).\(column)", times: 2)
        }

        // "Done" only exists once the engine reports the grid complete.
        awaitAndTap(app.buttons["game.done"], "game.done never appeared after placing five stars")

        assertLabelEquals(element("gameResults.headline"), "Solved!")
        awaitElement(element("gameResults.score"), "gameResults.score never appeared")
        awaitElement(element("gameResults.time"), "gameResults.time never appeared")
        awaitElement(element("gameResults.share"), "gameResults.share never appeared")
    }

    // MARK: - 2b. Solving the fake Trail puzzle

    func testSolveFakeTrail() {
        let app = launch(state: "returning")

        openHubRow("trail")
        awaitElement(element("trail.cell.0.0"), "The Trail grid never appeared",
                     timeout: KithUITestCase.launchTimeout)

        // The path always starts at waypoint 1, (0,0); the snake from TESTING.md §3 visits
        // the remaining eight cells in this order.
        for (row, column) in [(0, 1), (0, 2), (1, 2), (1, 1), (1, 0), (2, 0), (2, 1), (2, 2)] {
            tapCell("trail.cell.\(row).\(column)")
        }

        awaitAndTap(app.buttons["game.done"], "game.done never appeared after completing the trail")

        awaitElement(element("gameResults.headline"), "gameResults.headline never appeared")
    }

    // MARK: - 2c. Solving the fake Quint puzzle

    func testSolveFakeQuint() {
        let app = launch(state: "returning")

        openHubRow("quint")
        awaitElement(element("quint.tile.0.0"), "The Quint grid never appeared",
                     timeout: KithUITestCase.launchTimeout)

        // "slate" (wrong), then "crane" (the fake's answer, TESTING.md §3).
        for letter in "slate" {
            awaitAndTap(element("quint.key.\(letter)"), "quint.key.\(letter) never appeared")
        }
        awaitAndTap(element("quint.key.enter"), "quint.key.enter never appeared")

        for letter in "crane" {
            awaitAndTap(element("quint.key.\(letter)"), "quint.key.\(letter) never appeared")
        }
        awaitAndTap(element("quint.key.enter"), "quint.key.enter never appeared")

        // A solving guess submits on its own (no Done tap needed) via the same completion
        // path the other games' Done button uses.
        awaitElement(element("gameResults.headline"), "gameResults.headline never appeared")
    }

    // MARK: - 3. Giving up on Duo

    func testGiveUpDuo() {
        let app = launch(state: "returning")

        openHubRow("duo")
        awaitElement(element("duo.cell.0.0"), "The Duo grid never appeared",
                     timeout: KithUITestCase.launchTimeout)

        awaitAndTap(app.buttons["game.giveUp"], "game.giveUp never appeared")

        // The destructive button in a `confirmationDialog` does not always surface its
        // identifier, so fall back to its title ("Give up" — the toolbar item is labelled
        // "Give up on this game", so the two never collide).
        let confirm = element("game.giveUp.confirm")
        if confirm.waitForExistence(timeout: KithUITestCase.timeout) {
            confirm.tap()
        } else {
            awaitAndTap(app.buttons["Give up"], "The give-up confirmation never appeared")
        }

        assertLabelEquals(element("gameResults.headline"), "Gave up")
        assertLabelContains(element("gameResults.score"), "100")
    }

    // MARK: - 4. Expanding a board section

    /// docs/07 "Boards (revised 2026-09-13)": the picker/period controls are gone; the
    /// Board tab is one expandable section per game. Quint is collapsed by default
    /// (only "All games" starts expanded), so tapping its section header should reveal
    /// its rows on demand.
    ///
    /// Mum and Sam are also friends under "All games", which is always expanded — so a
    /// plain `board.row.u-mum` / `board.row.u-sam` existence check after expanding Quint
    /// would pass even if Quint never rendered anything (finding B5). Instead this asserts
    /// on Dev's "failed" row, which only exists under Quint.
    func testBoardQuintSectionExpands() {
        launch(state: "played")

        tapTab("tab.board")

        awaitElement(element("board.section.total"), "board.section.total never appeared")
        // The Quint header is the last section: below the fold behind the expanded All
        // games rows, so the List has not created it until we scroll.
        let quint = scrollUntilExists(element("board.section.quint"))
        awaitElement(quint, "board.section.quint never appeared after scrolling")

        // Quint is collapsed by default; expanding it loads and reveals its rows (Mum and
        // Sam solve every grid/Quint board in the fake, TESTING.md §2).
        awaitAndTap(quint, "board.section.quint never became tappable")

        let failed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'board.row.' AND label CONTAINS 'failed'"))
            .firstMatch
        scrollUntilExists(failed)
        awaitElement(failed, "No board row showed \"failed\" after expanding Quint")
    }
}
