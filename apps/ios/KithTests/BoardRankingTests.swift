// BoardRankingTests.swift — docs/07-games-hub.md §Product rules → "Boards (revised
// 2026-09-13)". Pure unit tests of `AppModel.rankRows` / `rankYesterday` /
// `rankMovement` / `timeLabel`: no `FakeKithAPI`, no `AppModel` instance — every row is
// a hand-built `BoardRow` so the ranking rules are exercised directly.

import Foundation
import KithCore
import LineupEngine
import XCTest
@testable import Kith

@MainActor
final class BoardRankingTests: XCTestCase {

    // MARK: Helpers

    /// A solved row: `solved_count`/`played_count` both 1, `elapsed_ms` set.
    private func solvedRow(_ id: String, name: String, elapsedMs: Int,
                           prevElapsedMs: Int? = nil, prevSolved: Bool? = nil) -> BoardRow {
        let prev = prevSolved ?? (prevElapsedMs != nil)
        return BoardRow(user_id: id, display_name: name, score: 100, elapsed_ms: elapsedMs,
                        played: true, solved_count: 1, played_count: 1,
                        prev_played: prev, prev_elapsed_ms: prevElapsedMs,
                        prev_solved_count: prev ? 1 : 0, prev_played_count: prev ? 1 : 0)
    }

    /// A played-but-not-solved row ("gave up" / "failed"): `played_count` 1, `solved_count` 0.
    private func attemptedRow(_ id: String, name: String) -> BoardRow {
        BoardRow(user_id: id, display_name: name, score: 10, played: true,
                solved_count: 0, played_count: 1,
                prev_played: false, prev_solved_count: 0, prev_played_count: 0)
    }

    /// A row that hasn't played at all.
    private func unplayedRow(_ id: String, name: String) -> BoardRow {
        BoardRow(user_id: id, display_name: name, score: 0, played: false,
                solved_count: 0, played_count: 0,
                prev_played: false, prev_solved_count: 0, prev_played_count: 0)
    }

    // MARK: Per-game ordering

    func testPerGameOrdersSolvedByElapsedThenGaveUpThenUnplayed() {
        let rows = [
            solvedRow("u-slow", name: "Slow", elapsedMs: 90_000),
            attemptedRow("u-gaveup", name: "GaveUp"),
            unplayedRow("u-never", name: "Never"),
            solvedRow("u-fast", name: "Fast", elapsedMs: 30_000),
        ]

        let ranked = AppModel.rankRows(rows, game: .stars)

        XCTAssertEqual(ranked.map(\.row.user_id), ["u-fast", "u-slow", "u-gaveup", "u-never"])
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 3, nil])
        XCTAssertEqual(ranked.map(\.solved), [true, true, false, false])
        XCTAssertEqual(ranked.map(\.attempted), [false, false, true, false])
    }

    func testPerGameTiesBrokenByDisplayName() {
        let rows = [
            solvedRow("u-b", name: "Bea", elapsedMs: 40_000),
            solvedRow("u-a", name: "Ada", elapsedMs: 40_000),
        ]

        let ranked = AppModel.rankRows(rows, game: .duo)

        XCTAssertEqual(ranked.map(\.row.display_name), ["Ada", "Bea"])
        XCTAssertEqual(ranked.map(\.rank), [1, 2])
    }

    // MARK: All-games ordering

    func testAllGamesOrdersBySolvedCountThenElapsedAscending() {
        // Explicit solved_count/elapsed_ms for the "total" game — not derived from any
        // per-game row, since `total` is its own summed column (docs/07).
        let mostGamesSlow = BoardRow(user_id: "u-mostSlow", display_name: "MostSlow", score: 300,
                                     elapsed_ms: 200_000, played: true,
                                     solved_count: 3, played_count: 3)
        let mostGamesFast = BoardRow(user_id: "u-mostFast", display_name: "MostFast", score: 300,
                                     elapsed_ms: 100_000, played: true,
                                     solved_count: 3, played_count: 3)
        let fewerGames = BoardRow(user_id: "u-fewer", display_name: "Fewer", score: 100,
                                  elapsed_ms: 10_000, played: true,
                                  solved_count: 1, played_count: 1)
        let never = unplayedRow("u-never", name: "Never")

        let ranked = AppModel.rankRows([mostGamesSlow, fewerGames, mostGamesFast, never], game: .total)

        XCTAssertEqual(ranked.map(\.row.user_id), ["u-mostFast", "u-mostSlow", "u-fewer", "u-never"])
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 3, nil])
    }

    // MARK: Yesterday's ranking

    func testYesterdayRankingUsesPrevFields() {
        // Today Fast beats Slow; yesterday it was the other way round.
        let fast = solvedRow("u-fast", name: "Fast", elapsedMs: 30_000, prevElapsedMs: 90_000)
        let slow = solvedRow("u-slow", name: "Slow", elapsedMs: 90_000, prevElapsedMs: 30_000)

        let today = AppModel.rankRows([fast, slow], game: .stars)
        let yesterday = AppModel.rankYesterday([fast, slow], game: .stars)

        XCTAssertEqual(today.first(where: { $0.row.user_id == "u-fast" })?.rank, 1)
        XCTAssertEqual(yesterday.first(where: { $0.row.user_id == "u-fast" })?.rank, 2)
        XCTAssertEqual(yesterday.first(where: { $0.row.user_id == "u-slow" })?.rank, 1)
    }

    // MARK: Movement arithmetic

    func testRankMovementIsPrevRankMinusRank() {
        XCTAssertEqual(AppModel.rankMovement(rank: 1, prevRank: 3), 2, "climbed 2 places")
        XCTAssertEqual(AppModel.rankMovement(rank: 3, prevRank: 1), -2, "fell 2 places")
        XCTAssertEqual(AppModel.rankMovement(rank: 2, prevRank: 2), 0)
    }

    func testRankMovementIsNilWhenEitherSideIsAbsent() {
        XCTAssertNil(AppModel.rankMovement(rank: nil, prevRank: 1))
        XCTAssertNil(AppModel.rankMovement(rank: 1, prevRank: nil))
        XCTAssertNil(AppModel.rankMovement(rank: nil, prevRank: nil))
    }

    // MARK: Today's time-column labels

    func testGridGameLabelsGaveUpAndDash() {
        XCTAssertEqual(AppModel.timeLabel(for: solvedRow("u1", name: "A", elapsedMs: 45_000), game: .stars),
                       "0:45")
        XCTAssertEqual(AppModel.timeLabel(for: attemptedRow("u2", name: "B"), game: .duo), "gave up")
        XCTAssertEqual(AppModel.timeLabel(for: unplayedRow("u3", name: "C"), game: .trail), "—")
    }

    func testQuintLabelsFailedInsteadOfGaveUp() {
        XCTAssertEqual(AppModel.timeLabel(for: attemptedRow("u1", name: "A"), game: .quint), "failed")
    }

    /// Lineup's solved/failed state comes from `attempts` (the classic tries rule), not
    /// `solved_count`, so a fixture with attempts but no counts still labels correctly.
    func testLineupSolvedAndFailedLabelsFromAttempts() {
        let solvedAttempt = Attempt(order: [1, 2, 3], feedback: [.correct, .correct, .correct], elapsedMs: 26_000)
        let failedAttempt = Attempt(order: [2, 1, 3], feedback: [.correct, .wrong, .wrong], elapsedMs: 90_000)

        let solved = BoardRow(user_id: "u1", display_name: "A", score: 900, elapsed_ms: 26_000,
                              attempts: [solvedAttempt], played: true)
        let failed = BoardRow(user_id: "u2", display_name: "B", score: 100, elapsed_ms: 90_000,
                              attempts: [failedAttempt], played: true)
        let neverPlayed = BoardRow(user_id: "u3", display_name: "C", score: 0, played: false)

        XCTAssertEqual(AppModel.timeLabel(for: solved, game: .lineup), "0:26")
        XCTAssertEqual(AppModel.timeLabel(for: failed, game: .lineup), "—")
        XCTAssertEqual(AppModel.timeLabel(for: neverPlayed, game: .lineup), "—")
    }

    // MARK: Yesterday's caption

    func testYesterdayLabel() {
        let solvedYesterday = solvedRow("u1", name: "A", elapsedMs: 45_000, prevElapsedMs: 72_000)
        let notSolvedYesterday = solvedRow("u2", name: "B", elapsedMs: 45_000)

        XCTAssertEqual(AppModel.yesterdayLabel(for: solvedYesterday), "yesterday 1:12")
        XCTAssertEqual(AppModel.yesterdayLabel(for: notSolvedYesterday), "yesterday —")
    }
}
