// GamesTests.swift — the games-hub unit tests from `apps/ios/PLAN-games.md` §"Tests".
//
// Everything runs against `FakeKithAPI`'s tiny deterministic puzzles (TESTING.md §3,
// "Games hub"): Stars 5×5 with the solution `[1, 3, 0, 2, 4]`, Duo 6×6 with six blanks on
// the leading diagonal, Trail 3×3 with a forced snake.

import Foundation
import GridGames
import KithCore
import XCTest
@testable import Kith

@MainActor
final class GamesTests: XCTestCase {

    // MARK: Helpers

    /// Boots a signed-in model with today's games loaded.
    private func ready() async -> Harness {
        let harness = Harness(.returning)
        await harness.boot()
        return harness
    }

    /// Places the five stars of the fake puzzle by cycling each cell twice
    /// (empty → ✕ → ★), which is exactly what the UI test taps.
    private func solveStars(_ model: AppModel) {
        for (row, column) in FakeKithAPI.starsSolution.enumerated() {
            let point = GridPoint(row: row, col: column)
            model.starsCycle(at: point)
            model.starsCycle(at: point)
        }
    }

    // MARK: 1. The hub

    func testHubListsFourGames() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        XCTAssertEqual(HubGame.allCases.count, 4)
        XCTAssertEqual(model.dailyGames.count, 3)
        for kind in GameKind.allCases {
            XCTAssertTrue(model.isAvailable(kind), "\(kind.rawValue) should be available today")
            XCTAssertTrue(model.isHubRowEnabled(.grid(kind)))
            XCTAssertEqual(model.hubStatus(for: .grid(kind)), "Not played")
        }
        XCTAssertEqual(model.hubStatus(for: .lineup), "Not played")
    }

    func testHubMarksAGameUnavailableWhenTheServerHasNoRow() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        model.dailyGames = model.dailyGames.filter { $0.game != .trail }

        XCTAssertFalse(model.isAvailable(.trail))
        XCTAssertFalse(model.isHubRowEnabled(.grid(.trail)))
        XCTAssertEqual(model.hubStatus(for: .grid(.trail)), "Not available today")
    }

    // MARK: 2. Starting a game

    func testStartingStarsCreatesAStarsEngine() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)

        let active = try XCTUnwrap(model.activeGame)
        XCTAssertEqual(active.kind, .stars)
        XCTAssertEqual(active.mistakes, 0)
        XCTAssertNil(active.finished)
        guard case .stars(let engine) = active.engine else {
            return XCTFail("Expected a StarsEngine, got \(active.engine)")
        }
        XCTAssertEqual(engine.spec.n, 5)
        XCTAssertEqual(engine.starCount, 0)
        XCTAssertTrue(harness.api.calls.contains("startGame(stars)"))
    }

    func testStartingTheSameGameTwiceDoesNotRestartTheClock() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        let revealedAt = try XCTUnwrap(model.activeGame?.revealedAt)
        await model.startGame(.stars)

        XCTAssertEqual(model.activeGame?.revealedAt, revealedAt)
        XCTAssertEqual(harness.callCount("startGame"), 1)
    }

    /// Finding A1: opening Duo while Stars is mid-round must not discard the Stars session.
    func testStartingADifferentGameKeepsTheOtherUnfinished() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        model.starsCycle(at: GridPoint(row: 0, col: 1))
        let starsAfterOneMove = try XCTUnwrap(model.activeGames[.stars])
        XCTAssertEqual(starsAfterOneMove.moves, 1)

        await model.startGame(.duo)

        // Stars is still there, untouched, even though a different game is now open.
        XCTAssertEqual(model.activeGames[.stars], starsAfterOneMove)
        XCTAssertEqual(model.activeGames[.duo]?.kind, .duo)
        XCTAssertEqual(model.activeGame?.kind, .duo, "the convenience accessor follows whichever kind was opened last")
    }

    // MARK: 3. Completing a game

    func testCompletingFakeStarsSubmitsTheAnswerAndStoresTheResult() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        solveStars(model)

        XCTAssertTrue(try XCTUnwrap(model.activeGame).engine.isComplete)

        await model.finishGame()

        let submission = try XCTUnwrap(harness.api.gameSubmissions.last)
        XCTAssertEqual(submission.game, .stars)
        XCTAssertFalse(submission.gaveUp)
        XCTAssertEqual(submission.answerJSON, "{\"stars\":[1,3,0,2,4]}")

        let stored = try XCTUnwrap(model.result(for: .stars))
        XCTAssertTrue(stored.solved)
        XCTAssertFalse(stored.gaveUp)
        XCTAssertEqual(stored.score, GameScoring.score(elapsedMs: stored.elapsedMs, gaveUp: false))
        XCTAssertTrue(model.showGameResults)
        XCTAssertEqual(model.hubStatus(for: .grid(.stars)),
                       "Solved · \(AppModel.clock(stored.elapsedMs))")
    }

    func testDoneDoesNothingWhileTheGridIsIncomplete() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        model.starsCycle(at: GridPoint(row: 0, col: 1))
        await model.finishGame()

        XCTAssertTrue(harness.api.gameSubmissions.isEmpty)
        XCTAssertNil(model.result(for: .stars))
        XCTAssertFalse(model.showGameResults)
    }

    // MARK: 4. Giving up

    func testGiveUpSubmitsGaveUpAndScoresOneHundred() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.duo)
        await model.giveUpGame()

        let submission = try XCTUnwrap(harness.api.gameSubmissions.last)
        XCTAssertEqual(submission.game, .duo)
        XCTAssertTrue(submission.gaveUp)
        XCTAssertNil(submission.answerJSON)

        let stored = try XCTUnwrap(model.result(for: .duo))
        XCTAssertTrue(stored.gaveUp)
        XCTAssertEqual(stored.score, 100)
        XCTAssertEqual(AppModel.gameHeadline(stored), "Gave up")
        XCTAssertEqual(model.hubStatus(for: .grid(.duo)), "Gave up")
    }

    // MARK: 5. Mistakes

    func testMistakesIncrementOnANewConflict() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)

        // Two stars in the same region (row 0) is a conflict; the second one books it.
        let first = GridPoint(row: 0, col: 0)
        model.starsCycle(at: first)
        model.starsCycle(at: first)
        XCTAssertEqual(model.activeGame?.mistakes, 0)

        let second = GridPoint(row: 0, col: 2)
        model.starsCycle(at: second)
        model.starsCycle(at: second)
        XCTAssertEqual(model.activeGame?.mistakes, 1)

        // Taking the offending star away again is not a second mistake.
        model.starsCycle(at: second)
        XCTAssertEqual(model.activeGame?.mistakes, 1)
    }

    func testResetClearsTheGridButKeepsTheSession() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        solveStars(model)
        model.resetGame()

        guard case .stars(let engine) = try XCTUnwrap(model.activeGame).engine else {
            return XCTFail("Expected a StarsEngine")
        }
        XCTAssertEqual(engine.starCount, 0)
        XCTAssertNotNil(model.activeGame)
    }

    // MARK: 6. Offline queue

    func testOfflineGameSubmitQueuesAndReplays() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        harness.api.failNextGameSubmit = true

        await model.startGame(.stars)
        solveStars(model)
        await model.finishGame()

        // The player still sees a result, computed with the server's own scoring rule.
        let local = try XCTUnwrap(model.result(for: .stars))
        XCTAssertTrue(local.solved)
        XCTAssertTrue(model.gamePendingSync)
        XCTAssertEqual(model.queuedGameResults.count, 1)
        XCTAssertEqual(model.queuedGameResults.first?.game, .stars)
        XCTAssertEqual(model.queuedGameResults.first?.stars, FakeKithAPI.starsSolution)

        await model.retryQueuedGames()

        XCTAssertFalse(model.gamePendingSync)
        XCTAssertTrue(model.queuedGameResults.isEmpty)
        XCTAssertEqual(harness.callCount("submitGame"), 2)
        XCTAssertEqual(harness.api.gameSubmissions.last?.answerJSON, "{\"stars\":[1,3,0,2,4]}")
    }

    func testAlreadyPlayedGameIsTreatedAsSuccess() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.trail)
        await model.giveUpGame()
        XCTAssertNotNil(model.result(for: .trail))

        // A second submission for the same day is a 409; nothing should be queued.
        model.activeGames[.trail] = nil
        model.gameResults = [:]
        await model.startGame(.trail)
        await model.giveUpGame()

        XCTAssertTrue(model.queuedGameResults.isEmpty)
        XCTAssertFalse(model.gamePendingSync)
        XCTAssertNotNil(model.result(for: .trail))
    }

    // MARK: 7. Board cache

    func testBoardCacheIsKeyedByGame() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.refreshBoard(kind: .friends, scopeId: nil, period: .today, game: .stars)
        await model.refreshBoard(kind: .friends, scopeId: nil, period: .today, game: .total)

        let lineup = BoardCacheKey(kind: .friends, scopeId: nil, period: .today,
                                   date: model.today, game: .lineup)
        let stars = BoardCacheKey(kind: .friends, scopeId: nil, period: .today,
                                  date: model.today, game: .stars)
        let total = BoardCacheKey(kind: .friends, scopeId: nil, period: .today,
                                  date: model.today, game: .total)

        XCTAssertNotEqual(stars, lineup)
        XCTAssertNotNil(model.boards[lineup], "bootstrap caches the Lineup board")
        XCTAssertNotNil(model.boards[stars])
        XCTAssertNotNil(model.boards[total])
        XCTAssertTrue(harness.api.calls.contains("board(friends,today,stars)"))
        XCTAssertTrue(harness.api.calls.contains("board(friends,today,total)"))
    }

    /// `BoardDisplayRow` carries no time, so the grid-game boards read it back off the raw
    /// cached rows instead; the friends seed (TESTING.md §2) gives Mum/Sam/Dev distinct
    /// times and leaves Jo unplayed.
    func testElapsedMsByUserOnAGridGameBoard() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.refreshBoard(kind: .friends, scopeId: nil, period: .today, game: .stars)

        let elapsed = model.elapsedMsByUser(kind: .friends, scopeId: nil, period: .today, game: .stars)

        XCTAssertEqual(elapsed["u-mum"], 26_000)
        XCTAssertEqual(elapsed["u-sam"], 45_000)
        XCTAssertEqual(elapsed["u-dev"], 120_000)
        XCTAssertNil(elapsed["u-jo"], "Jo hasn't played, so there is no time to show")
    }

    // MARK: The other two engines

    func testFakeDuoLeavesSixBlanksAndCompletes() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.duo)
        guard case .duo(let engine) = try XCTUnwrap(model.activeGame).engine else {
            return XCTFail("Expected a DuoEngine")
        }
        let blanks = (0..<6).flatMap { row in
            (0..<6).compactMap { column in
                engine.cells[row][column] == nil ? GridPoint(row: row, col: column) : nil
            }
        }
        XCTAssertEqual(blanks, FakeKithAPI.duoBlanks)

        // Fill each blank with its solution value: one tap for ●, two for ○.
        for point in blanks {
            let value = FakeKithAPI.duoSolution[point.row][point.col]
            model.duoCycle(at: point)
            if value == 1 { model.duoCycle(at: point) }
        }

        // (1,1) has to pass through ● on its way to ○, which is transiently a fourth ● in
        // row 1 — but that first tap of any cycle is never the player's final answer, so
        // `duoCycle` does not book it as a mistake (finding B2). Nothing else in this
        // sequence creates a conflict that survives its move, so the count stays zero.
        XCTAssertEqual(model.activeGame?.mistakes, 0)
        XCTAssertTrue(try XCTUnwrap(model.activeGame).engine.isComplete)

        await model.finishGame()
        XCTAssertEqual(harness.api.gameSubmissions.last?.gaveUp, false)
        XCTAssertEqual(model.result(for: .duo)?.solved, true)
    }

    func testFakeTrailIsSolvedByTheSnake() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.trail)
        for step in FakeKithAPI.trailPath.dropFirst() {
            model.trailExtend(to: GridPoint(row: step[0], col: step[1]))
        }

        XCTAssertTrue(try XCTUnwrap(model.activeGame).engine.isComplete)

        await model.finishGame()
        let submission = try XCTUnwrap(harness.api.gameSubmissions.last)
        XCTAssertEqual(submission.game, .trail)
        XCTAssertEqual(submission.answerJSON,
                       "{\"path\":[[0,0],[0,1],[0,2],[1,2],[1,1],[1,0],[2,0],[2,1],[2,2]]}")
    }

    // MARK: Stars paint-drag

    func testStarsPaintCross() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)

        let empty = GridPoint(row: 0, col: 0)
        model.starsPaintCross(at: empty)
        guard case .stars(let painted) = try XCTUnwrap(model.activeGame).engine else {
            return XCTFail("Expected a StarsEngine")
        }
        XCTAssertEqual(painted.marks[0][0], .cross)

        // Painting an already-marked cell again is refused: a ✕ never becomes anything
        // else through a drag stroke.
        model.starsPaintCross(at: empty)
        guard case .stars(let stillCrossed) = try XCTUnwrap(model.activeGame).engine else {
            return XCTFail("Expected a StarsEngine")
        }
        XCTAssertEqual(stillCrossed.marks[0][0], .cross)

        // A star is never disturbed by a paint stroke either — only an empty cell can
        // become a ✕ this way.
        let starPoint = GridPoint(row: 1, col: 3)
        model.starsCycle(at: starPoint)
        model.starsCycle(at: starPoint)
        model.starsPaintCross(at: starPoint)
        guard case .stars(let untouched) = try XCTUnwrap(model.activeGame).engine else {
            return XCTFail("Expected a StarsEngine")
        }
        XCTAssertEqual(untouched.marks[1][3], .star)
    }

    // MARK: No-start retry (backend round: submit-game 409 "no_start")

    func testGameSubmitRetriesStartOnceAfterNoStart() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        solveStars(model)

        harness.api.failNextGameSubmitWithNoStart = true
        await model.finishGame()

        // The first submit came back `no_start`; the model replayed `startGame` once and
        // retried, and the retry succeeded, so nothing is queued.
        XCTAssertEqual(harness.callCount("startGame"), 2)
        XCTAssertEqual(harness.callCount("submitGame"), 2)
        XCTAssertFalse(model.gamePendingSync)
        XCTAssertTrue(model.queuedGameResults.isEmpty)
        let stored = try XCTUnwrap(model.result(for: .stars))
        XCTAssertTrue(stored.solved)
    }

    func testGameSubmitQueuesWhenTheNoStartRetryAlsoFails() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        solveStars(model)

        // The first submit throws `no_start`; the replayed `startGame` succeeds (the fake
        // never fails that call) but the retried submit hits the still-armed offline flag,
        // so the result ends up queued rather than looping a second retry.
        harness.api.failNextGameSubmitWithNoStart = true
        harness.api.failNextGameSubmit = true
        await model.finishGame()

        XCTAssertEqual(harness.callCount("startGame"), 2)
        XCTAssertEqual(harness.callCount("submitGame"), 2)
        XCTAssertTrue(model.gamePendingSync)
        XCTAssertEqual(model.queuedGameResults.count, 1)
        XCTAssertEqual(model.queuedGameResults.first?.game, .stars)
    }

    // MARK: Profile and heatmap

    func testProfileStatsAndHeatmapCountGridGames() async throws {
        let harness = await ready()
        defer { harness.cleanUp() }
        let model = harness.model

        await model.startGame(.stars)
        solveStars(model)
        await model.finishGame()
        await model.refreshGameResults()

        let stars = try XCTUnwrap(model.gameStats.first { $0.game == .stars })
        XCTAssertEqual(stars.daysPlayed, 1)
        XCTAssertNotNil(stars.bestMs)

        let trail = try XCTUnwrap(model.gameStats.first { $0.game == .trail })
        XCTAssertEqual(trail.daysPlayed, 0)
        XCTAssertNil(trail.bestMs)

        // The heatmap has one cell per day of the last eight weeks and must not lose the
        // Lineup history when grid-game days are folded in.
        XCTAssertEqual(model.heatmap.count, 56)
    }
}
