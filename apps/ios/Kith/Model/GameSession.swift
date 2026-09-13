// GameSession.swift — the app's wrapper around the four `GridGames` engines.
//
// `AppModel` owns exactly one of these at a time (`activeGame`). The engines are value
// types, so every move is "copy, mutate, assign back", which is what makes SwiftUI see
// the change through `@Observable`.

import Foundation
import GridGames
import KithCore

/// Whichever engine the open game needs. PLAN-games.md spells this out as
/// `GameEngine { case stars(StarsEngine), duo(DuoEngine), trail(TrailEngine) }`; `quint`
/// (`QuintEngine`) was added alongside it (docs/07 §Quint).
enum GameEngine: Equatable, Sendable {
    case stars(StarsEngine)
    case duo(DuoEngine)
    case trail(TrailEngine)
    case quint(QuintEngine)

    /// Builds the engine that matches the spec `start_game` returned.
    init(spec: GameSpec) throws {
        switch spec {
        case .stars(let starsSpec):
            self = .stars(try StarsEngine(spec: starsSpec))
        case .duo(let duoSpec):
            self = .duo(try DuoEngine(spec: duoSpec))
        case .trail(let trailSpec):
            self = .trail(try TrailEngine(spec: trailSpec))
        case .quint(let quintSpec):
            self = .quint(try QuintEngine(spec: quintSpec))
        }
    }

    var kind: GameKind {
        switch self {
        case .stars: return .stars
        case .duo: return .duo
        case .trail: return .trail
        case .quint: return .quint
        }
    }

    var isComplete: Bool {
        switch self {
        case .stars(let engine): return engine.isComplete
        case .duo(let engine): return engine.isComplete
        case .trail(let engine): return engine.isComplete
        case .quint(let engine): return engine.isComplete
        }
    }

    /// Cells the engine currently considers in violation. Trail has no notion of a
    /// conflicting cell — an illegal step is simply refused — so it reports none. Quint has
    /// no notion of a conflict either: a bad guess is simply refused by `submit()`.
    var conflicts: Set<GridPoint> {
        switch self {
        case .stars(let engine): return engine.conflicts
        case .duo(let engine): return engine.conflicts
        case .trail: return []
        case .quint: return []
        }
    }

    /// The `answer` field of a `submit-game` request, or nil while the grid is unfinished.
    /// Quint's answer (the guesses made) is only meaningful once the puzzle is solved or
    /// failed, exactly like the other three engines' `answer`.
    var answer: GameAnswer? {
        switch self {
        case .stars(let engine):
            guard let stars = engine.answer else { return nil }
            return .stars(stars)
        case .duo(let engine):
            guard let cells = engine.answer else { return nil }
            return .duo(cells)
        case .trail(let engine):
            guard let path = engine.answer else { return nil }
            return .trail(path)
        case .quint(let engine):
            guard engine.isComplete else { return nil }
            return .quint(engine.guessesAnswer)
        }
    }

    func shareRows() -> [String] {
        switch self {
        case .stars(let engine): return engine.shareRows()
        case .duo(let engine): return engine.shareRows()
        case .trail(let engine): return engine.shareRows()
        case .quint(let engine): return engine.shareRows()
        }
    }

    /// Side length of the grid, for the layout maths in the three square grid views. Quint's
    /// board is 6×5, not square; `n` (5) is returned so the size-based paddings/thresholds in
    /// `GameHostView`/`GridMetrics` (all keyed off "≥ 9") still make a sane decision, even
    /// though `QuintView` never actually reads this property for its own layout.
    var size: Int {
        switch self {
        case .stars(let engine): return engine.spec.n
        case .duo(let engine): return engine.spec.n
        case .trail(let engine): return engine.spec.n
        case .quint(let engine): return engine.spec.n
        }
    }

    mutating func reset() {
        switch self {
        case .stars(let current):
            var engine = current
            engine.reset()
            self = .stars(engine)
        case .duo(let current):
            var engine = current
            engine.reset()
            self = .duo(engine)
        case .trail(let current):
            var engine = current
            engine.reset()
            self = .trail(engine)
        case .quint(let current):
            var engine = current
            engine.reset()
            self = .quint(engine)
        }
    }
}

/// One grid game in progress (or just finished). PLAN-games.md: `StartedGame`, the engine,
/// `revealedAt`, `mistakes`, `isFinishing`.
struct ActiveGame: Equatable, Sendable {
    let started: StartedGame
    var engine: GameEngine
    /// When the puzzle first became visible; the timer and `elapsedMs` run from here.
    var revealedAt: Date
    /// Incremented whenever a move puts a cell into conflict that was not in conflict before.
    var mistakes: Int = 0
    /// Every accepted move. Only used as a `.sensoryFeedback` trigger.
    var moves: Int = 0
    /// Bumped by `AppModel.quintSubmit()` on a `.notAWord` outcome so `QuintView` can
    /// trigger its shake animation as a `.onChange` side effect. Unused by the other games.
    var quintShake: Int = 0
    var isFinishing: Bool = false
    /// Set once `submit-game` (or the offline queue) has produced a result.
    var finished: StoredGameResult?

    var kind: GameKind { started.game }
    var number: Int { started.number }

    var elapsedMs: Int {
        max(0, Int(Date().timeIntervalSince(revealedAt) * 1000))
    }
}

/// One line of the profile's per-game breakdown. File scope rather than nested in
/// `AppModel`, so it does not inherit that class's `@MainActor` isolation and can satisfy
/// `Identifiable`'s nonisolated `id` requirement (same reason as `RevealLine`).
struct GameStat: Identifiable, Equatable, Sendable {
    var id: String { game.rawValue }
    let game: GameKind
    let daysPlayed: Int
    /// Fastest solve in milliseconds, or nil when nothing has been solved.
    let bestMs: Int?
}
