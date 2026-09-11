// Presenters.swift — pure transforms from wire rows to what the screens draw.
// See docs/03-wireframes.md. No Foundation formatting beyond String; no I/O.
//
// CONTRACT FILE.

import Foundation
import LineupEngine

// MARK: - Board

public enum RankMovement: Sendable, Equatable {
    case up(Int)
    case down(Int)
    case same
    case new
    /// Not applicable (row has not played).
    case none

    /// Chip text: "▲2", "▼1", "–", "NEW", or "" for `.none`.
    public var chipText: String {
        switch self {
        case .up(let delta): return "▲\(delta)"
        case .down(let delta): return "▼\(delta)"
        case .same: return "–"
        case .new: return "NEW"
        case .none: return ""
        }
    }
}

public struct BoardDisplayRow: Sendable, Equatable, Identifiable {
    public var id: String { userId }
    public let userId: String
    public let name: String
    public let initials: String
    public let isMe: Bool
    public let played: Bool
    public let score: Int
    public let rank: Int?
    public let movement: RankMovement
    /// Squares of the final attempt (5 entries) for the Today view, else empty.
    public let miniGrid: [TileFeedback]
    /// Taunt text if visible.
    public let taunt: String?
    /// Reactions received, in `reactionEmoji` order, deduplicated.
    public let reactions: [String]
    /// The emoji the viewer has given this row today, if any.
    public let myReaction: String?
}

public enum BoardPresenter {
    /// Initials: first letters of the first two whitespace-separated words, uppercased ("Dev from work" → "DF",
    /// "Mum" → "M", "" → "?").
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return "?" }
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    /// Movement from `rank`/`prev_rank`: both present → up/down/same by difference; rank present and
    /// prev nil → `.new`; rank nil → `.none`.
    public static func movement(rank: Int?, prev: Int?) -> RankMovement {
        guard let rank else { return .none }
        guard let prev else { return .new }
        if rank < prev { return .up(prev - rank) }
        if rank > prev { return .down(rank - prev) }
        return .same
    }

    /// Builds display rows preserving server order (played first by score, then unplayed).
    /// - `name`: `nameOverride[userId]` (address-book name) if present, else `display_name`; the viewer's own row is named "You".
    /// - `miniGrid`: feedback of the LAST attempt when `period == .today` and attempts exist, else [].
    /// - `taunt`: the taunt for that user if present in `taunts`.
    /// - `reactions`: emoji from `reactions` where `to_user == userId`, deduped, ordered by `reactionEmoji`.
    /// - `myReaction`: the emoji where `from_user == me && to_user == userId`.
    public static func rows(_ rows: [BoardRow], me: String, period: BoardPeriod,
                            nameOverride: [String: String], taunts: [Taunt], reactions: [Reaction]) -> [BoardDisplayRow] {
        rows.map { row in
            let isMe = row.user_id == me
            let name = isMe ? "You" : (nameOverride[row.user_id] ?? row.display_name)

            let miniGrid: [TileFeedback]
            if period == .today, let attempts = row.attempts, let last = attempts.last {
                miniGrid = last.feedback
            } else {
                miniGrid = []
            }

            let taunt = taunts.first(where: { $0.user_id == row.user_id })?.text

            let received = Set(reactions.filter { $0.to_user == row.user_id }.map(\.emoji))
            let orderedReactions = reactionEmoji.filter { received.contains($0) }
            let myReaction = reactions.first(where: { $0.from_user == me && $0.to_user == row.user_id })?.emoji

            return BoardDisplayRow(
                userId: row.user_id,
                name: name,
                initials: initials(name),
                isMe: isMe,
                played: row.played,
                score: row.score,
                rank: row.rank,
                movement: movement(rank: row.rank, prev: row.prev_rank),
                miniGrid: miniGrid,
                taunt: taunt,
                reactions: orderedReactions,
                myReaction: myReaction
            )
        }
    }

    /// "5 of 9 friends played today" (singular/plural on the second number: "1 friend").
    public static func headerText(played: Int, total: Int) -> String {
        let word = total == 1 ? "friend" : "friends"
        return "\(played) of \(total) \(word) played today"
    }
}

// MARK: - Results screen

public struct ResultsSummary: Sendable, Equatable {
    /// "Solved in 2" or "Not this time"
    public let headline: String
    public let score: Int
    /// "0:48"
    public let timeText: String
    public let grid: [[TileFeedback]]
    public let streak: Int
    /// "You're #2 of 5 friends today ▲1", nil when no friend has played.
    public let rankTeaser: String?
    public let shareText: String
}

public enum ResultsPresenter {
    /// `friendRows` is the Friends board for the same date; the teaser uses the viewer's rank and the
    /// number of rows with `played == true`, and movement chip text when not `.none`/`.same`.
    public static func summary(result: PuzzleResult, puzzleNumber: Int, streak: Int, refCode: String?,
                               friendRows: [BoardRow], me: String) -> ResultsSummary {
        let headline = result.solved ? "Solved in \(result.tries)" : "Not this time"

        let totalSeconds = max(result.elapsedMs, 0) / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let timeText = "\(minutes):" + String(format: "%02d", seconds)

        let grid = result.attempts.map(\.feedback)
        let shareText = ShareText.render(result: result, puzzleNumber: puzzleNumber, streak: streak, refCode: refCode)

        let othersPlayed = friendRows.filter { $0.played && $0.user_id != me }.count
        var rankTeaser: String?
        if othersPlayed > 0 {
            let playedCount = friendRows.filter(\.played).count
            let myRow = friendRows.first(where: { $0.user_id == me })
            let rank = myRow?.rank ?? 0
            var teaser = "You're #\(rank) of \(playedCount) friends today"
            let movement = BoardPresenter.movement(rank: myRow?.rank, prev: myRow?.prev_rank)
            switch movement {
            case .none, .same:
                break
            case .up, .down, .new:
                teaser += " \(movement.chipText)"
            }
            rankTeaser = teaser
        }

        return ResultsSummary(
            headline: headline,
            score: result.score,
            timeText: timeText,
            grid: grid,
            streak: streak,
            rankTeaser: rankTeaser,
            shareText: shareText
        )
    }
}

// MARK: - Profile / streak

public enum HeatCell: Sendable, Equatable {
    case missed
    case played
    case solvedFirstTry
    case future
}

public struct ProfileStats: Sendable, Equatable {
    public let daysPlayed: Int
    /// 0...1
    public let solveRate: Double
    public let averageScore: Int
    /// Counts of tries 1, 2, 3, and fails.
    public let triesHistogram: [Int]
    public let longestStreak: Int
}

public enum ProfilePresenter {
    /// 8 columns × 7 rows (56 cells) ending on `today`, oldest first, Monday-start weeks: the last
    /// column is the week containing `today`; cells after `today` are `.future`.
    public static func heatmap(results: [ResultSummary], today: String) -> [HeatCell] {
        let currentWeekMonday = LocalDay.weekStart(today)
        let start = LocalDay.shift(currentWeekMonday, by: -49)

        var byDate: [String: ResultSummary] = [:]
        for result in results {
            byDate[result.puzzle_date] = result
        }

        var cells: [HeatCell] = []
        cells.reserveCapacity(56)
        for i in 0..<56 {
            let date = LocalDay.shift(start, by: i)
            if date > today {
                cells.append(.future)
            } else if let result = byDate[date] {
                cells.append(result.solved && result.tries == 1 ? .solvedFirstTry : .played)
            } else {
                cells.append(.missed)
            }
        }
        return cells
    }

    /// Stats over all results; `longestStreak` is the longest run of consecutive dates.
    public static func stats(results: [ResultSummary]) -> ProfileStats {
        let daysPlayed = results.count
        let solvedCount = results.filter(\.solved).count
        let solveRate = daysPlayed == 0 ? 0.0 : Double(solvedCount) / Double(daysPlayed)
        let totalScore = results.reduce(0) { $0 + $1.score }
        let averageScore = daysPlayed == 0 ? 0 : Int((Double(totalScore) / Double(daysPlayed)).rounded())

        var histogram = [0, 0, 0, 0]
        for result in results {
            if !result.solved {
                histogram[3] += 1
            } else if (1...3).contains(result.tries) {
                histogram[result.tries - 1] += 1
            }
        }

        let longestStreak = longestConsecutiveRun(of: results.map(\.puzzle_date))

        return ProfileStats(
            daysPlayed: daysPlayed,
            solveRate: solveRate,
            averageScore: averageScore,
            triesHistogram: histogram,
            longestStreak: longestStreak
        )
    }

    private static func longestConsecutiveRun(of dates: [String]) -> Int {
        let sorted = Set(dates).sorted()
        guard !sorted.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for i in 1..<sorted.count {
            if LocalDay.shift(sorted[i - 1], by: 1) == sorted[i] {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }
        return longest
    }
}

// MARK: - Invites

/// The one place that spells an invite link, so the three share sheets (board empty
/// state, the friends-found tail, the profile invite row) cannot drift apart.
public enum InvitePresenter {
    /// With a puzzle number: "Play today's Lineup with me on Kith: <webBase>/p/<n>?r=<code>".
    /// Without one: "Join me on Kith: <webBase>/c/<code>".
    public static func text(webBase: String, code: String, puzzleNumber: Int?) -> String {
        if let puzzleNumber {
            return "Play today's Lineup with me on Kith: \(webBase)/p/\(puzzleNumber)?r=\(code)"
        }
        return "Join me on Kith: \(webBase)/c/\(code)"
    }
}

// MARK: - Onboarding

/// Pure state machine for docs/02 §6. The app drives it with events and renders `step`.
public enum OnboardingStep: Sendable, Equatable {
    case phone
    case code(phone: String)
    case name
    case contactsPrompt
    case playing
    case done
}

public enum OnboardingEvent: Sendable, Equatable {
    case phoneEntered(String)
    case codeVerified
    case back
    case nameSaved
    case contactsDecided
    case firstResultShown
}

public struct OnboardingFlow: Sendable, Equatable {
    public private(set) var step: OnboardingStep = .phone
    public init() {}

    /// Transitions: phone --phoneEntered(p)--> code(p); code --codeVerified--> name; code --back--> phone;
    /// name --nameSaved--> contactsPrompt; contactsPrompt --contactsDecided--> playing;
    /// playing --firstResultShown--> done. Any other (event, step) pair is ignored.
    public mutating func apply(_ event: OnboardingEvent) {
        switch (step, event) {
        case (.phone, .phoneEntered(let phone)):
            step = .code(phone: phone)
        case (.code, .codeVerified):
            step = .name
        case (.code, .back):
            step = .phone
        case (.name, .nameSaved):
            step = .contactsPrompt
        case (.contactsPrompt, .contactsDecided):
            step = .playing
        case (.playing, .firstResultShown):
            step = .done
        default:
            break
        }
    }

    /// 0...1 progress for the four-segment bar: phone 0.0, code 0.25, name 0.5, contactsPrompt 0.75, else 1.0.
    public var progress: Double {
        switch step {
        case .phone: return 0.0
        case .code: return 0.25
        case .name: return 0.5
        case .contactsPrompt: return 0.75
        case .playing, .done: return 1.0
        }
    }
}
