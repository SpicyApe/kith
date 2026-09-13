// Quint.swift — Wordle-style: guess the five-letter word in six tries. CONTRACT FILE partner
// to Common.swift's QuintSpec/QuintMark; this is the engine implementation (docs/07 §Quint).

import Foundation

/// Value-type state for one Quint puzzle.
public struct QuintEngine: Sendable, Equatable {
    public let spec: QuintSpec
    /// Accepted guesses, in order, lowercase.
    public private(set) var guesses: [String]
    /// The row currently being typed (not yet submitted).
    public private(set) var current: String

    /// Outcome of `submit()`.
    public enum SubmitOutcome: Equatable {
        case accepted
        case notAWord
        case tooShort
        case finished
    }

    /// Validates `spec.n == 5` and `spec.answer` is exactly 5 lowercase ASCII letters.
    /// Throws `GridError.invalidSpec`. Starts with no guesses and an empty current row.
    public init(spec: QuintSpec) throws {
        guard spec.n == 5 else {
            throw GridError.invalidSpec("n must be 5")
        }
        guard spec.answer.count == 5,
              spec.answer.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) else {
            throw GridError.invalidSpec("answer must be 5 lowercase letters")
        }
        self.spec = spec
        self.guesses = []
        self.current = ""
    }

    /// Appends a lowercased letter to `current`. Ignores (returns false) anything but a–z,
    /// or when the row is already full (`spec.n` letters) or the puzzle is already complete.
    @discardableResult
    public mutating func type(_ letter: Character) -> Bool {
        guard !isComplete, current.count < spec.n else { return false }
        let lower = Character(String(letter).lowercased())
        guard lower.isASCII, ("a"..."z").contains(lower) else { return false }
        current.append(lower)
        return true
    }

    /// Removes the last letter of `current`, if any. No-op once the puzzle is complete.
    public mutating func backspace() {
        guard !isComplete, !current.isEmpty else { return }
        current.removeLast()
    }

    /// Validates and, on success, moves `current` into `guesses`.
    public mutating func submit() -> SubmitOutcome {
        if isComplete { return .finished }
        guard current.count == spec.n else { return .tooShort }
        guard QuintWords.isAllowed(current) else { return .notAWord }
        guesses.append(current)
        current = ""
        return .accepted
    }

    /// Standard Wordle duplicate-letter rule: hits are marked first, then remaining guess
    /// letters are marked `.near` left to right while unmatched copies of that letter remain
    /// in `answer`, else `.miss`.
    public static func marks(guess: String, answer: String) -> [QuintMark] {
        let g = Array(guess)
        let a = Array(answer)
        let n = a.count
        var result = Array(repeating: QuintMark.miss, count: n)
        var remaining: [Character: Int] = [:]
        for i in 0..<n {
            if i < g.count, g[i] == a[i] {
                result[i] = .hit
            } else {
                remaining[a[i], default: 0] += 1
            }
        }
        for i in 0..<min(n, g.count) where result[i] != .hit {
            if let count = remaining[g[i]], count > 0 {
                result[i] = .near
                remaining[g[i]] = count - 1
            }
        }
        return result
    }

    /// Marks for an already-submitted row, or nil if `row` hasn't been guessed yet.
    public func marks(for row: Int) -> [QuintMark]? {
        guard guesses.indices.contains(row) else { return nil }
        return Self.marks(guess: guesses[row], answer: spec.answer)
    }

    /// Each letter's best mark so far, across every submitted guess (for the on-screen keyboard).
    public var keyMarks: [Character: QuintMark] {
        var best: [Character: QuintMark] = [:]
        for row in guesses.indices {
            guard let rowMarks = marks(for: row) else { continue }
            let letters = Array(guesses[row])
            for i in 0..<min(letters.count, rowMarks.count) {
                let letter = letters[i]
                let mark = rowMarks[i]
                if let existing = best[letter] {
                    best[letter] = max(existing, mark)
                } else {
                    best[letter] = mark
                }
            }
        }
        return best
    }

    public var isSolved: Bool {
        guesses.last == spec.answer
    }

    /// Six guesses used, none correct.
    public var isFailed: Bool {
        !isSolved && guesses.count >= spec.guesses
    }

    public var isComplete: Bool {
        isSolved || isFailed
    }

    /// Wrong guesses, shown as "mistakes" on the results screen.
    public var wrongGuesses: Int {
        guesses.filter { $0 != spec.answer }.count
    }

    /// The guesses made so far, lowercase, in order. The app wraps this as `GameAnswer.quint`.
    public var guessesAnswer: [String] {
        guesses
    }

    /// Mirrors `quintShareRows`: one row per guess, ⬛️/🟨/🟩 for miss/near/hit.
    public func shareRows() -> [String] {
        guesses.map { guess in
            Self.marks(guess: guess, answer: spec.answer).map { mark -> String in
                switch mark {
                case .hit: return "🟩"
                case .near: return "🟨"
                case .miss: return "⬛️"
                }
            }.joined()
        }
    }

    /// Clears all guesses and the current row.
    public mutating func reset() {
        guesses = []
        current = ""
    }
}
