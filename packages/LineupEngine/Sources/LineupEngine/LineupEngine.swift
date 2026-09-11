// LineupEngine — the pure, UI-free state machine for the daily "Lineup" puzzle.
//
// CONTRACT FILE. Every public declaration below, including doc comments, is the
// interface the app and the tests are written against. Implementers fill the bodies
// and may add `internal`/`private` helpers, but must not change public signatures,
// add public API, or alter documented behaviour. See docs/02-v1-feature-spec.md §1.
//
// The engine is deterministic and time-agnostic: the caller supplies elapsed
// milliseconds at each submission. No Date, no randomness, no I/O.

import Foundation

// MARK: - Puzzle payload

/// One tile. `id` is the server's `list_items.id`; `label` is what the tile shows.
public struct PuzzleItem: Hashable, Codable, Sendable {
    public let id: Int
    public let label: String

    public init(id: Int, label: String) {
        self.id = id
        self.label = label
    }
}

/// The daily puzzle as delivered to the client. Carries labels and the correct order
/// (needed for offline play and instant feedback) but never values or reveal facts;
/// those are fetched after submission. The server recomputes the score from the
/// attempt log regardless.
public struct Puzzle: Codable, Sendable, Equatable {
    /// Calendar date the puzzle belongs to, `YYYY-MM-DD`, the same worldwide.
    public let date: String
    /// Sequential puzzle number shown in the UI and share text (`Kith #142`).
    public let number: Int
    /// e.g. "Order these by the year they were invented"
    public let prompt: String
    /// e.g. "Earliest at the top"
    public let direction: String
    /// Exactly 5 items in the **shuffled presentation order** the player first sees.
    public let items: [PuzzleItem]
    /// Exactly 5 item ids, top to bottom, in the correct order. Must be a permutation
    /// of `items.map(\.id)`.
    public let correctOrder: [Int]

    public init(date: String, number: Int, prompt: String, direction: String,
                items: [PuzzleItem], correctOrder: [Int]) {
        self.date = date
        self.number = number
        self.prompt = prompt
        self.direction = direction
        self.items = items
        self.correctOrder = correctOrder
    }
}

// MARK: - Attempts and results

/// Per-position feedback after a submission.
/// JSON raw values are shared with the server (`results.attempts` jsonb).
public enum TileFeedback: String, Codable, Sendable, Equatable {
    /// The item is in its correct position. It becomes locked.
    case correct
    /// The item's correct position is exactly one slot above or below where it is.
    case near
    /// Anything else.
    case wrong
}

/// One submission. `order` is item ids top to bottom; `feedback[i]` describes `order[i]`.
/// Encodes to `{"order":[...],"feedback":["correct","near",...],"elapsedMs":48210}`.
public struct Attempt: Codable, Sendable, Equatable {
    public let order: [Int]
    public let feedback: [TileFeedback]
    /// Milliseconds since the puzzle was revealed, as reported by the caller.
    public let elapsedMs: Int

    public init(order: [Int], feedback: [TileFeedback], elapsedMs: Int) {
        self.order = order
        self.feedback = feedback
        self.elapsedMs = elapsedMs
    }

    /// True when every position is `.correct`.
    public var isSolved: Bool { feedback.allSatisfy { $0 == .correct } }
}

/// The finished outcome. Available once the engine's phase is `.solved` or `.failed`.
public struct PuzzleResult: Codable, Sendable, Equatable {
    public let puzzleDate: String
    /// Number of submissions made (1...3).
    public let tries: Int
    public let solved: Bool
    /// Elapsed milliseconds of the final submission.
    public let elapsedMs: Int
    /// Computed by `Scoring.score(tries:solved:elapsedMs:)`.
    public let score: Int
    public let attempts: [Attempt]

    public init(puzzleDate: String, tries: Int, solved: Bool, elapsedMs: Int,
                score: Int, attempts: [Attempt]) {
        self.puzzleDate = puzzleDate
        self.tries = tries
        self.solved = solved
        self.elapsedMs = elapsedMs
        self.score = score
        self.attempts = attempts
    }
}

public enum Phase: Sendable, Equatable {
    case playing
    case solved
    case failed
}

public enum LineupError: Error, Equatable, Sendable {
    /// The puzzle failed validation. The string is a human-readable reason.
    case invalidPuzzle(String)
    /// A move touched a locked position (index given).
    case positionLocked(Int)
    /// A position index outside 0..<5.
    case positionOutOfRange(Int)
    /// `move` or `submit` was called after the puzzle was solved or failed.
    case notPlaying
    /// `submit` was called while `canSubmit` is false (the order is unchanged).
    case nothingChanged
    /// `elapsedMs` is negative or smaller than the previous attempt's value.
    case invalidElapsed
}

// MARK: - Engine

/// Value-type state machine. Copy it freely; every mutation is explicit.
///
/// Lifecycle: `init` validates the puzzle and starts in `.playing` with
/// `currentOrder == puzzle.items.map(\.id)`. The player calls `move` to reorder
/// unlocked tiles and `submit` up to `maxTries` times. After a solve, or after the
/// third submission, the phase becomes `.solved`/`.failed` and `result` is non-nil.
public struct LineupEngine: Sendable, Equatable {
    public static let maxTries = 3
    public static let tileCount = 5

    public let puzzle: Puzzle
    public private(set) var attempts: [Attempt]
    /// Item ids top to bottom as currently arranged on screen.
    public private(set) var currentOrder: [Int]

    /// Validates the puzzle:
    /// - exactly `tileCount` items with unique ids
    /// - `correctOrder` has `tileCount` entries and is a permutation of the item ids
    /// - `date` matches `^\d{4}-\d{2}-\d{2}$`
    /// - the presentation order (`items.map(\.id)`) must not already equal `correctOrder`
    /// Throws `LineupError.invalidPuzzle` with a reason otherwise.
    public init(puzzle: Puzzle) throws {
        guard puzzle.items.count == Self.tileCount else {
            throw LineupError.invalidPuzzle("items must contain exactly \(Self.tileCount) entries")
        }
        let itemIds = puzzle.items.map(\.id)
        guard Set(itemIds).count == Self.tileCount else {
            throw LineupError.invalidPuzzle("item ids must be unique")
        }
        guard puzzle.correctOrder.count == Self.tileCount else {
            throw LineupError.invalidPuzzle("correctOrder must contain exactly \(Self.tileCount) entries")
        }
        guard Set(puzzle.correctOrder) == Set(itemIds) else {
            throw LineupError.invalidPuzzle("correctOrder must be a permutation of the item ids")
        }
        guard itemIds != puzzle.correctOrder else {
            throw LineupError.invalidPuzzle("presentation order must not equal correctOrder")
        }
        guard Self.isValidDateFormat(puzzle.date) else {
            throw LineupError.invalidPuzzle("date must match YYYY-MM-DD")
        }

        self.puzzle = puzzle
        self.attempts = []
        self.currentOrder = itemIds
    }

    /// Checks `date` against `^\d{4}-\d{2}-\d{2}$` without relying on a regex engine.
    private static func isValidDateFormat(_ date: String) -> Bool {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else {
            return false
        }
        return parts.allSatisfy { part in part.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    // MARK: Derived state

    /// `.playing` until a solved attempt or the third attempt; then `.solved`/`.failed`.
    public var phase: Phase {
        if let last = attempts.last, last.isSolved {
            return .solved
        }
        if attempts.count == Self.maxTries {
            return .failed
        }
        return .playing
    }

    /// Positions (0..<5) whose tile was `.correct` in the most recent attempt.
    /// Empty before the first submission. Locked positions never change afterwards
    /// because `move` refuses to touch them, so the set only ever grows.
    public var lockedPositions: Set<Int> {
        guard let last = attempts.last else { return [] }
        return Set(last.feedback.indices.filter { last.feedback[$0] == .correct })
    }

    public var triesRemaining: Int {
        Self.maxTries - attempts.count
    }

    /// True only while `.playing` and `currentOrder` differs from the last submitted
    /// order (or from the initial presentation order when nothing has been submitted).
    /// Drives the enabled state of the "Lock in" button.
    public var canSubmit: Bool {
        phase == .playing && currentOrder != (attempts.last?.order ?? puzzle.items.map(\.id))
    }

    /// Non-nil once the phase is `.solved` or `.failed`. `tries == attempts.count`,
    /// `elapsedMs` is the last attempt's, `score` from `Scoring`.
    public var result: PuzzleResult? {
        guard phase == .solved || phase == .failed, let last = attempts.last else { return nil }
        return PuzzleResult(
            puzzleDate: puzzle.date,
            tries: attempts.count,
            solved: last.isSolved,
            elapsedMs: last.elapsedMs,
            score: Scoring.score(tries: attempts.count, solved: last.isSolved, elapsedMs: last.elapsedMs),
            attempts: attempts
        )
    }

    // MARK: Mutations

    /// Moves the tile at position `from` so that it lands at position `to`, shifting
    /// the tiles in between, **while locked tiles stay exactly where they are**.
    ///
    /// Precisely: take the unlocked positions in ascending order as a sub-list; both
    /// `from` and `to` must be members of it (else `positionLocked`). Remove the item
    /// at `from` from the sub-list and insert it at `to`'s index within the sub-list,
    /// then write the sub-list back into the unlocked positions in ascending order.
    /// `from == to` is a no-op. Throws `positionOutOfRange` for indices outside 0..<5
    /// and `notPlaying` after the puzzle ends.
    public mutating func move(from: Int, to: Int) throws {
        guard phase == .playing else { throw LineupError.notPlaying }
        guard (0..<Self.tileCount).contains(from) else { throw LineupError.positionOutOfRange(from) }
        guard (0..<Self.tileCount).contains(to) else { throw LineupError.positionOutOfRange(to) }

        let locked = lockedPositions
        let unlockedPositions = (0..<Self.tileCount).filter { !locked.contains($0) }

        guard unlockedPositions.contains(from) else { throw LineupError.positionLocked(from) }
        guard unlockedPositions.contains(to) else { throw LineupError.positionLocked(to) }

        guard from != to else { return }

        var subList = unlockedPositions.map { currentOrder[$0] }
        let fromIndex = unlockedPositions.firstIndex(of: from)!
        let toIndex = unlockedPositions.firstIndex(of: to)!
        let moved = subList.remove(at: fromIndex)
        subList.insert(moved, at: toIndex)

        for (index, position) in unlockedPositions.enumerated() {
            currentOrder[position] = subList[index]
        }
    }

    /// Submits `currentOrder`. Computes feedback with `Self.feedback(for:correctOrder:)`,
    /// appends the attempt, and returns it. After this call the phase may have changed.
    ///
    /// Throws `notPlaying`, `nothingChanged` (see `canSubmit`), or `invalidElapsed`
    /// when `elapsedMs < 0` or `elapsedMs < attempts.last?.elapsedMs`.
    @discardableResult
    public mutating func submit(elapsedMs: Int) throws -> Attempt {
        guard phase == .playing else { throw LineupError.notPlaying }
        guard canSubmit else { throw LineupError.nothingChanged }
        if elapsedMs < 0 || (attempts.last.map({ elapsedMs < $0.elapsedMs }) ?? false) {
            throw LineupError.invalidElapsed
        }

        let feedback = Self.feedback(for: currentOrder, correctOrder: puzzle.correctOrder)
        let attempt = Attempt(order: currentOrder, feedback: feedback, elapsedMs: elapsedMs)
        attempts.append(attempt)
        return attempt
    }

    // MARK: Pure helpers

    /// Feedback for an arbitrary order against the correct order. Both arrays are
    /// item ids, top to bottom, and must be the same length. For each position `i`:
    /// `.correct` if `order[i] == correctOrder[i]`; otherwise `.near` if the correct
    /// position of `order[i]` is `i - 1` or `i + 1`; otherwise `.wrong`.
    public static func feedback(for order: [Int], correctOrder: [Int]) -> [TileFeedback] {
        order.enumerated().map { index, id in
            if index < correctOrder.count, correctOrder[index] == id { return .correct }
            guard let correctIndex = correctOrder.firstIndex(of: id) else { return .wrong }
            if correctIndex == index - 1 || correctIndex == index + 1 { return .near }
            return .wrong
        }
    }
}

// MARK: - Scoring

/// Mirrors `supabase/functions/_shared/lineup.ts`. Keep the two in lock-step.
public enum Scoring {
    /// Base points: solved on try 1 → 1000, try 2 → 700, try 3 → 400.
    /// Time penalty, applied only when solved: `2 * min(elapsedMs / 1000, 120)`
    /// using integer division, so at most 240.
    /// Not solved → 100 flat, regardless of time.
    /// Any `tries` outside 1...3 or negative `elapsedMs` is clamped into range first.
    public static func score(tries: Int, solved: Bool, elapsedMs: Int) -> Int {
        let clampedTries = min(max(tries, 1), 3)
        guard solved else { return 100 }
        let clampedElapsedMs = max(elapsedMs, 0)
        let base = [1000, 700, 400][clampedTries - 1]
        let penalty = 2 * min(clampedElapsedMs / 1000, 120)
        return base - penalty
    }
}

// MARK: - Share text

/// Renders the plain-text block pasted into group chats.
public enum ShareText {
    /// Format, exactly:
    ///
    ///     Kith #142 · 2/3 · 0:48 🔥12
    ///     ⬜🟨🟩⬜🟨
    ///     🟩🟩🟩🟩🟩
    ///     kith.app/p/142?r=7F3Q
    ///
    /// - Line 1: `Kith #<number> · <tries>/3 · <m:ss>` where `<tries>` is `X` when not
    ///   solved; `<m:ss>` is `elapsedMs / 1000` as minutes and zero-padded seconds.
    ///   Append ` 🔥<streak>` only when `streak >= 1`.
    /// - One line per attempt: 🟩 for `.correct`, 🟨 for `.near`, ⬜ for `.wrong`.
    /// - Last line: `kith.app/p/<number>` plus `?r=<refCode>` when `refCode` is non-nil
    ///   and non-empty.
    /// - Lines joined with `\n`, no trailing newline.
    public static func render(result: PuzzleResult, puzzleNumber: Int, streak: Int,
                              refCode: String?) -> String {
        let triesText = result.solved ? "\(result.tries)" : "X"
        let totalSeconds = max(result.elapsedMs, 0) / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let time = "\(minutes):" + String(format: "%02d", seconds)
        let streakSuffix = streak >= 1 ? " 🔥\(streak)" : ""

        var lines = ["Kith #\(puzzleNumber) · \(triesText)/3 · \(time)\(streakSuffix)"]
        for attempt in result.attempts {
            lines.append(attempt.feedback.map(square).joined())
        }

        var link = "kith.app/p/\(puzzleNumber)"
        if let refCode, !refCode.isEmpty {
            link += "?r=\(refCode)"
        }
        lines.append(link)

        return lines.joined(separator: "\n")
    }

    private static func square(_ feedback: TileFeedback) -> String {
        switch feedback {
        case .correct: return "🟩"
        case .near: return "🟨"
        case .wrong: return "⬜"
        }
    }
}
