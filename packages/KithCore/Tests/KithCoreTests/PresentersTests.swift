import XCTest
@testable import KithCore
import LineupEngine

final class PresentersTests: XCTestCase {
    // MARK: BoardPresenter.initials

    func testInitialsFirstLettersOfFirstTwoWords() {
        XCTAssertEqual(BoardPresenter.initials("Dev from work"), "DF")
    }

    func testInitialsSingleWord() {
        XCTAssertEqual(BoardPresenter.initials("Mum"), "M")
    }

    func testInitialsEmptyString() {
        XCTAssertEqual(BoardPresenter.initials(""), "?")
    }

    func testInitialsTrimsSurroundingWhitespace() {
        XCTAssertEqual(BoardPresenter.initials("  alex  "), "A")
    }

    // MARK: BoardPresenter.movement

    func testMovementUpWhenRankImproves() {
        XCTAssertEqual(BoardPresenter.movement(rank: 1, prev: 3), .up(2))
    }

    func testMovementDownWhenRankWorsens() {
        XCTAssertEqual(BoardPresenter.movement(rank: 3, prev: 1), .down(2))
    }

    func testMovementSameWhenRankUnchanged() {
        XCTAssertEqual(BoardPresenter.movement(rank: 2, prev: 2), .same)
    }

    func testMovementNewWhenNoPreviousRank() {
        XCTAssertEqual(BoardPresenter.movement(rank: 1, prev: nil), .new)
    }

    func testMovementNoneWhenNotPlayed() {
        XCTAssertEqual(BoardPresenter.movement(rank: nil, prev: 5), .none)
        XCTAssertEqual(BoardPresenter.movement(rank: nil, prev: nil), .none)
    }

    // MARK: RankMovement.chipText

    func testChipText() {
        XCTAssertEqual(RankMovement.up(2).chipText, "▲2")
        XCTAssertEqual(RankMovement.down(1).chipText, "▼1")
        XCTAssertEqual(RankMovement.same.chipText, "–")
        XCTAssertEqual(RankMovement.new.chipText, "NEW")
        XCTAssertEqual(RankMovement.none.chipText, "")
    }

    // MARK: BoardPresenter.rows

    /// me: played, solved on the second (last) attempt.
    private let meRow = BoardRow(
        user_id: "me", display_name: "Me Real Name", score: 604, tries: 2, elapsed_ms: 48_210,
        attempts: [
            Attempt(order: [1, 2, 3, 4, 5], feedback: [.wrong, .wrong, .wrong, .wrong, .wrong], elapsedMs: 20_000),
            Attempt(order: [1, 2, 3, 4, 5], feedback: [.correct, .correct, .correct, .correct, .correct], elapsedMs: 48_210),
        ],
        played: true, rank: 1, prev_rank: 2
    )

    /// A friend with a taunt and reactions, including a duplicate emoji and the
    /// viewer's own reaction.
    private let friendWithTauntRow = BoardRow(
        user_id: "f1", display_name: "Server Name F1", score: 700, tries: 1, elapsed_ms: 30_000,
        attempts: [Attempt(order: [1, 2, 3, 4, 5], feedback: [.correct, .near, .wrong, .near, .correct], elapsedMs: 30_000)],
        played: true, rank: 2, prev_rank: 1
    )

    /// A friend who hasn't played today.
    private let unplayedRow = BoardRow(
        user_id: "f2", display_name: "Unplayed Friend", score: 0, tries: nil, elapsed_ms: nil,
        attempts: nil, played: false, rank: nil, prev_rank: nil
    )

    /// A friend the viewer has in their address book under a different name.
    private let overriddenRow = BoardRow(
        user_id: "f3", display_name: "Server Name F3", score: 400, tries: 3, elapsed_ms: 60_000,
        attempts: [Attempt(order: [1, 2, 3, 4, 5], feedback: [.wrong, .wrong, .wrong, .wrong, .wrong], elapsedMs: 60_000)],
        played: true, rank: 3, prev_rank: nil
    )

    private var fixtureRows: [BoardRow] { [meRow, friendWithTauntRow, unplayedRow, overriddenRow] }

    private let fixtureTaunts = [Taunt(user_id: "f1", puzzle_date: "2026-09-11", text: "gg")]

    private let fixtureReactions = [
        Reaction(from_user: "other1", to_user: "f1", puzzle_date: "2026-09-11", emoji: "🔥"),
        Reaction(from_user: "other2", to_user: "f1", puzzle_date: "2026-09-11", emoji: "🔥"), // duplicate emoji
        Reaction(from_user: "other3", to_user: "f1", puzzle_date: "2026-09-11", emoji: "👏"),
        Reaction(from_user: "me", to_user: "f1", puzzle_date: "2026-09-11", emoji: "😂"),      // viewer's own reaction
    ]

    func testRowsPreservesServerOrder() {
        let rows = BoardPresenter.rows(
            fixtureRows, me: "me", period: .today,
            nameOverride: ["f3": "Contact Name F3"], taunts: fixtureTaunts, reactions: fixtureReactions
        )
        XCTAssertEqual(rows.map(\.userId), ["me", "f1", "f2", "f3"])
    }

    func testRowsNamesMeIsYouAndOverrideWinsOverDisplayName() {
        let rows = BoardPresenter.rows(
            fixtureRows, me: "me", period: .today,
            nameOverride: ["f3": "Contact Name F3"], taunts: fixtureTaunts, reactions: fixtureReactions
        )
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.userId, $0) })

        XCTAssertEqual(byId["me"]?.name, "You")
        XCTAssertTrue(byId["me"]?.isMe ?? false)
        XCTAssertEqual(byId["f1"]?.name, "Server Name F1") // no override, server name
        XCTAssertFalse(byId["f1"]?.isMe ?? true)
        XCTAssertEqual(byId["f2"]?.name, "Unplayed Friend")
        XCTAssertEqual(byId["f3"]?.name, "Contact Name F3") // address-book override wins
    }

    func testRowsMiniGridIsLastAttemptFeedbackForTodayWhenPlayed() {
        let rows = BoardPresenter.rows(
            fixtureRows, me: "me", period: .today,
            nameOverride: [:], taunts: fixtureTaunts, reactions: fixtureReactions
        )
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.userId, $0) })

        XCTAssertEqual(byId["me"]?.miniGrid, [.correct, .correct, .correct, .correct, .correct])
        XCTAssertEqual(byId["f1"]?.miniGrid, [.correct, .near, .wrong, .near, .correct])
        XCTAssertEqual(byId["f2"]?.miniGrid, []) // unplayed -> no attempts -> empty
    }

    func testRowsMiniGridIsEmptyForWeekPeriodEvenWithAttempts() {
        let rows = BoardPresenter.rows(
            fixtureRows, me: "me", period: .week,
            nameOverride: [:], taunts: fixtureTaunts, reactions: fixtureReactions
        )
        for row in rows {
            XCTAssertEqual(row.miniGrid, [], "row \(row.userId) should have an empty miniGrid outside .today")
        }
    }

    func testRowsTaunt() {
        let rows = BoardPresenter.rows(
            fixtureRows, me: "me", period: .today,
            nameOverride: [:], taunts: fixtureTaunts, reactions: fixtureReactions
        )
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.userId, $0) })

        XCTAssertEqual(byId["f1"]?.taunt, "gg")
        XCTAssertNil(byId["f2"]?.taunt)
    }

    func testRowsReactionsAreDedupedOrderedAndMyReactionIsSeparate() {
        let rows = BoardPresenter.rows(
            fixtureRows, me: "me", period: .today,
            nameOverride: [:], taunts: fixtureTaunts, reactions: fixtureReactions
        )
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.userId, $0) })

        // 🔥🔥👏😂 on f1, deduped, ordered per `reactionEmoji` (🔥,👏,😂,😭,🫡,🙄).
        XCTAssertEqual(byId["f1"]?.reactions, ["🔥", "👏", "😂"])
        XCTAssertEqual(byId["f1"]?.myReaction, "😂")
        XCTAssertEqual(byId["f2"]?.reactions, [])
        XCTAssertNil(byId["f2"]?.myReaction)
    }

    // MARK: BoardPresenter.headerText

    func testHeaderTextPlural() {
        XCTAssertEqual(BoardPresenter.headerText(played: 5, total: 9), "5 of 9 friends played today")
    }

    func testHeaderTextSingular() {
        XCTAssertEqual(BoardPresenter.headerText(played: 1, total: 1), "1 of 1 friend played today")
    }

    // MARK: ResultsPresenter.summary

    private func solvedResult() -> PuzzleResult {
        let attempts = [
            Attempt(order: [1, 2, 3, 4, 5], feedback: [.wrong, .near, .wrong, .near, .correct], elapsedMs: 20_000),
            Attempt(order: [1, 2, 3, 4, 5], feedback: [.correct, .correct, .correct, .correct, .correct], elapsedMs: 48_210),
        ]
        return PuzzleResult(
            puzzleDate: "2026-09-11", tries: 2, solved: true, elapsedMs: 48_210,
            score: Scoring.score(tries: 2, solved: true, elapsedMs: 48_210), attempts: attempts
        )
    }

    private func failedResult() -> PuzzleResult {
        let attempts = (1...3).map { n in
            Attempt(order: [1, 2, 3, 4, 5], feedback: [.wrong, .wrong, .wrong, .wrong, .wrong], elapsedMs: n * 10_000)
        }
        return PuzzleResult(
            puzzleDate: "2026-09-11", tries: 3, solved: false, elapsedMs: 30_000,
            score: Scoring.score(tries: 3, solved: false, elapsedMs: 30_000), attempts: attempts
        )
    }

    func testSummaryHeadlineWhenSolved() {
        let summary = ResultsPresenter.summary(
            result: solvedResult(), puzzleNumber: 142, streak: 4, refCode: "7F3Q",
            friendRows: [], me: "me"
        )
        XCTAssertEqual(summary.headline, "Solved in 2")
    }

    func testSummaryHeadlineWhenNotSolved() {
        let summary = ResultsPresenter.summary(
            result: failedResult(), puzzleNumber: 142, streak: 0, refCode: nil,
            friendRows: [], me: "me"
        )
        XCTAssertEqual(summary.headline, "Not this time")
    }

    func testSummaryTimeText() {
        let summary = ResultsPresenter.summary(
            result: solvedResult(), puzzleNumber: 142, streak: 4, refCode: "7F3Q",
            friendRows: [], me: "me"
        )
        XCTAssertEqual(summary.timeText, "0:48")
    }

    func testSummaryGridEqualsAttemptsFeedback() {
        let result = solvedResult()
        let summary = ResultsPresenter.summary(
            result: result, puzzleNumber: 142, streak: 4, refCode: "7F3Q",
            friendRows: [], me: "me"
        )
        XCTAssertEqual(summary.grid, result.attempts.map(\.feedback))
    }

    func testSummaryRankTeaserNilWhenNoOtherFriendPlayed() {
        let summary = ResultsPresenter.summary(
            result: solvedResult(), puzzleNumber: 142, streak: 4, refCode: "7F3Q",
            friendRows: [], me: "me"
        )
        XCTAssertNil(summary.rankTeaser)
    }

    func testSummaryRankTeaserWithMovement() {
        let friendRows = [
            BoardRow(user_id: "other0", display_name: "P0", score: 1000, tries: 1, elapsed_ms: 10_000, attempts: nil, played: true, rank: 1, prev_rank: 1),
            BoardRow(user_id: "me", display_name: "Me", score: 604, tries: 2, elapsed_ms: 48_210, attempts: nil, played: true, rank: 2, prev_rank: 3),
            BoardRow(user_id: "other2", display_name: "P2", score: 500, tries: 3, elapsed_ms: 50_000, attempts: nil, played: true, rank: 3, prev_rank: 2),
            BoardRow(user_id: "other3", display_name: "P3", score: 300, tries: 3, elapsed_ms: 90_000, attempts: nil, played: true, rank: 4, prev_rank: 4),
            BoardRow(user_id: "other4", display_name: "P4", score: 100, tries: 3, elapsed_ms: 100_000, attempts: nil, played: true, rank: 5, prev_rank: 5),
        ]
        let summary = ResultsPresenter.summary(
            result: solvedResult(), puzzleNumber: 142, streak: 4, refCode: "7F3Q",
            friendRows: friendRows, me: "me"
        )
        XCTAssertEqual(summary.rankTeaser, "You're #2 of 5 friends today ▲1")
    }

    func testSummaryRankTeaserOmitsChipWhenMovementIsSame() {
        let friendRows = [
            BoardRow(user_id: "me", display_name: "Me", score: 604, tries: 2, elapsed_ms: 48_210, attempts: nil, played: true, rank: 1, prev_rank: 1),
            BoardRow(user_id: "other1", display_name: "P1", score: 500, tries: 3, elapsed_ms: 50_000, attempts: nil, played: true, rank: 2, prev_rank: 2),
            BoardRow(user_id: "other2", display_name: "P2", score: 300, tries: 3, elapsed_ms: 90_000, attempts: nil, played: true, rank: 3, prev_rank: 3),
        ]
        let summary = ResultsPresenter.summary(
            result: solvedResult(), puzzleNumber: 142, streak: 4, refCode: "7F3Q",
            friendRows: friendRows, me: "me"
        )
        XCTAssertEqual(summary.rankTeaser, "You're #1 of 3 friends today")
    }

    func testSummaryShareTextMatchesShareTextRender() {
        let result = solvedResult()
        let summary = ResultsPresenter.summary(
            result: result, puzzleNumber: 142, streak: 4, refCode: "7F3Q",
            friendRows: [], me: "me"
        )
        XCTAssertEqual(
            summary.shareText,
            ShareText.render(result: result, puzzleNumber: 142, streak: 4, refCode: "7F3Q")
        )
    }

    // MARK: ProfilePresenter.heatmap

    func testHeatmapHasFiftySixCells() {
        let cells = ProfilePresenter.heatmap(results: [], today: "2026-09-11")
        XCTAssertEqual(cells.count, 56)
    }

    func testHeatmapFutureCellsInTodaysWeek() {
        // today = Friday 2026-09-11; today's Monday-start week is 2026-09-07...09-13.
        // The last (8th) column is that week: Mon=index49 ... Sun=index55.
        // Sat (09-12) and Sun (09-13) are after today -> .future.
        let cells = ProfilePresenter.heatmap(results: [], today: "2026-09-11")
        XCTAssertEqual(cells[54], .future) // 2026-09-12, Saturday
        XCTAssertEqual(cells[55], .future) // 2026-09-13, Sunday
    }

    func testHeatmapSolvedFirstTryAtTheRightIndexAndMissedElsewhere() {
        let solvedOnThursday = ResultSummary(puzzle_date: "2026-09-10", tries: 1, solved: true, score: 1_000)
        let cells = ProfilePresenter.heatmap(results: [solvedOnThursday], today: "2026-09-11")

        // 2026-09-10 is the Thursday of today's week -> index 49 + 3 = 52.
        XCTAssertEqual(cells[52], .solvedFirstTry)
        // No result recorded for Wednesday (index 51) or today itself (index 53).
        XCTAssertEqual(cells[51], .missed)
        XCTAssertEqual(cells[53], .missed)
    }

    func testHeatmapIgnoresResultsOlderThanTheWindow() {
        let solvedOnThursday = ResultSummary(puzzle_date: "2026-09-10", tries: 1, solved: true, score: 1_000)
        let ancientResult = ResultSummary(puzzle_date: "2026-07-01", tries: 1, solved: true, score: 1_000)

        let cells = ProfilePresenter.heatmap(results: [solvedOnThursday, ancientResult], today: "2026-09-11")

        XCTAssertEqual(cells.count, 56)
        XCTAssertEqual(cells[52], .solvedFirstTry) // unaffected by the out-of-window result
    }

    // MARK: ProfilePresenter.stats

    func testStatsAreAllZeroForNoResults() {
        let stats = ProfilePresenter.stats(results: [])

        XCTAssertEqual(stats.daysPlayed, 0)
        XCTAssertEqual(stats.solveRate, 0)
        XCTAssertEqual(stats.averageScore, 0)
        XCTAssertEqual(stats.triesHistogram, [0, 0, 0, 0])
        XCTAssertEqual(stats.longestStreak, 0)
    }

    func testStatsWithKnownFixture() {
        // 09-05, 09-06, 09-07 are three consecutive days (streak of 3); 09-09 and
        // 09-11 are each isolated (09-08 and 09-10 are missing), so the longest
        // streak is 3.
        let results = [
            ResultSummary(puzzle_date: "2026-09-05", tries: 1, solved: true, score: 1_000),
            ResultSummary(puzzle_date: "2026-09-06", tries: 2, solved: true, score: 700),
            ResultSummary(puzzle_date: "2026-09-07", tries: 3, solved: true, score: 400),
            ResultSummary(puzzle_date: "2026-09-09", tries: 3, solved: false, score: 100),
            ResultSummary(puzzle_date: "2026-09-11", tries: 1, solved: true, score: 900),
        ]
        let stats = ProfilePresenter.stats(results: results)

        XCTAssertEqual(stats.daysPlayed, 5)
        XCTAssertEqual(stats.solveRate, 0.8, accuracy: 0.0001) // 4 solved / 5 played
        XCTAssertEqual(stats.averageScore, 620) // (1000+700+400+100+900)/5
        XCTAssertEqual(stats.triesHistogram, [2, 1, 1, 1]) // tries1, tries2, tries3, fails
        XCTAssertEqual(stats.longestStreak, 3)
    }

    // MARK: OnboardingFlow

    func testOnboardingFlowHappyPath() {
        var flow = OnboardingFlow()
        XCTAssertEqual(flow.step, .phone)
        XCTAssertEqual(flow.progress, 0.0)

        flow.apply(.phoneEntered("+15551234567"))
        XCTAssertEqual(flow.step, .code(phone: "+15551234567"))
        XCTAssertEqual(flow.progress, 0.25)

        flow.apply(.codeVerified)
        XCTAssertEqual(flow.step, .name)
        XCTAssertEqual(flow.progress, 0.5)

        flow.apply(.nameSaved)
        XCTAssertEqual(flow.step, .contactsPrompt)
        XCTAssertEqual(flow.progress, 0.75)

        flow.apply(.contactsDecided)
        XCTAssertEqual(flow.step, .playing)
        XCTAssertEqual(flow.progress, 1.0)

        flow.apply(.firstResultShown)
        XCTAssertEqual(flow.step, .done)
        XCTAssertEqual(flow.progress, 1.0)
    }

    func testOnboardingFlowBackFromCodeReturnsToPhone() {
        var flow = OnboardingFlow()
        flow.apply(.phoneEntered("+15551234567"))
        flow.apply(.back)

        XCTAssertEqual(flow.step, .phone)
        XCTAssertEqual(flow.progress, 0.0)
    }

    func testOnboardingFlowIgnoresEventsThatDontMatchTheCurrentStep() {
        var flow = OnboardingFlow()

        flow.apply(.codeVerified) // not valid from .phone
        XCTAssertEqual(flow.step, .phone)

        flow.apply(.back) // not valid from .phone
        XCTAssertEqual(flow.step, .phone)

        flow.apply(.phoneEntered("+15551234567"))
        flow.apply(.nameSaved) // not valid from .code
        XCTAssertEqual(flow.step, .code(phone: "+15551234567"))

        flow.apply(.codeVerified)
        flow.apply(.firstResultShown) // not valid from .name
        XCTAssertEqual(flow.step, .name)
    }

    // MARK: - InvitePresenter

    func testInviteTextWithAPuzzleNumberLinksToTodaysPuzzle() {
        XCTAssertEqual(
            InvitePresenter.text(webBase: "https://kith.app", code: "ABCD12", puzzleNumber: 142),
            "Play today's Lineup with me on Kith: https://kith.app/p/142?r=ABCD12"
        )
    }

    func testInviteTextWithoutAPuzzleNumberLinksToTheCode() {
        XCTAssertEqual(
            InvitePresenter.text(webBase: "https://kith.app", code: "ABCD12", puzzleNumber: nil),
            "Join me on Kith: https://kith.app/c/ABCD12"
        )
    }
}
