// FakeKithAPI.swift — the in-memory backend behind `-uiTesting` and `KithTests`.
// See apps/ios/TESTING.md §2. Debug-only: nothing here ships.
//
// Concurrency: `KithAPI` is `Sendable` and its methods are plain `async` (not actor
// isolated), so this is a `final class` whose whole mutable state sits behind one
// `NSLock`, marked `@unchecked Sendable`. Every method takes the lock exactly once —
// `NSLock` is not recursive, so helpers that need state take it as a parameter rather
// than re-locking.
//
// KithCore's wire types are `public` structs with no `public init`, so their memberwise
// initializers are internal to that module and unreachable from here. The fake therefore
// keeps its data in local `Encodable` "seed" structs with identical field names and
// round-trips them through JSON to produce the real types (`convert(_:to:)`).

#if DEBUG

import Foundation
import GridGames
import KithCore
import LineupEngine

final class FakeKithAPI: KithAPI, @unchecked Sendable {

    // MARK: - Starting state

    enum State: String, Sendable, CaseIterable {
        /// Signed out; onboarding starts at the phone step.
        case fresh
        /// Signed in, registered, today unplayed.
        case returning
        /// Today already played, score 520.
        case played

        /// `-uiTestingState <name>`; anything unrecognised (or absent) is `fresh`.
        init(name: String?) {
            self = State(rawValue: name ?? "") ?? .fresh
        }
    }

    // MARK: - Fixed data (TESTING.md §2)

    static let meId = "u-me"
    static let meName = "Alex"
    static let meInviteCode = "KITH7F3Q"
    static let meTimeZone = "UTC"

    static let puzzleNumber = 142
    static let puzzlePrompt = "Order these by the year they were invented"
    static let puzzleDirection = "Earliest at the top"
    static let correctOrder = [1, 2, 3, 4, 5]
    /// One swap away from correct, so `LineupEngine`'s "presentation ≠ correct" check passes.
    static let presentationOrder = [2, 1, 3, 4, 5]

    static let circleName = "Family"
    static let circleCode = "ABC123"
    static let circleId = "c-family"
    static let circleOwner = "u-mum"

    struct FakeItem: Sendable {
        let id: Int
        let label: String
        let value: Double
        let fact: String
    }

    static let items: [FakeItem] = [
        FakeItem(id: 1, label: "Bicycle", value: 1817, fact: "The first version had no pedals"),
        FakeItem(id: 2, label: "Telephone", value: 1876, fact: "Bell's patent came in March 1876"),
        FakeItem(id: 3, label: "Light bulb", value: 1879, fact: "Edison's carbon-filament lamp"),
        FakeItem(id: 4, label: "Zipper", value: 1913, fact: "Sundback's design is the one still used"),
        FakeItem(id: 5, label: "Microwave oven", value: 1946,
                 fact: "Invented after a radar magnetron melted a chocolate bar"),
    ]

    /// The puzzle date the fake considers "today". TESTING.md pins this to UTC, so a
    /// simulator in another zone would disagree with `AppModel.today`; CI runs UTC.
    static func todayDate() -> String {
        LocalDay.date(Date(), tz: meTimeZone)
    }

    static func puzzle(for date: String) -> Puzzle {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tiles = presentationOrder.compactMap { id -> PuzzleItem? in
            guard let item = byId[id] else { return nil }
            return PuzzleItem(id: item.id, label: item.label)
        }
        return Puzzle(
            date: date,
            number: puzzleNumber,
            prompt: puzzlePrompt,
            direction: puzzleDirection,
            items: tiles,
            correctOrder: correctOrder
        )
    }

    // MARK: - Seeds (mirror KithCore's wire shapes field for field)

    private struct RowSeed: Encodable {
        var user_id: String
        var display_name: String
        var score: Int
        var tries: Int? = nil
        var elapsed_ms: Int? = nil
        var attempts: [Attempt]? = nil
        var played: Bool
        var rank: Int? = nil
        var prev_rank: Int? = nil
        // docs/07 "Boards (revised 2026-09-13)" / migration 0008: today's and yesterday's
        // counts, used by the client's own ranking instead of `rank`/`prev_rank` above.
        var solved_count: Int? = nil
        var played_count: Int? = nil
        var prev_score: Int? = nil
        var prev_played: Bool? = nil
        var prev_elapsed_ms: Int? = nil
        var prev_solved_count: Int? = nil
        var prev_played_count: Int? = nil
    }

    private struct CircleSeed: Encodable {
        var id: String
        var code: String
        var name: String
        var owner_id: String
    }

    private struct ReactionSeed: Encodable {
        var from_user: String
        var to_user: String
        var puzzle_date: String
        var emoji: String
    }

    private struct TauntSeed: Encodable {
        var user_id: String
        var puzzle_date: String
        var text: String
    }

    private struct ProfileSeed: Encodable {
        var id: String
        var display_name: String
        var tz: String
        var discoverable: Bool
        var invite_code: String
        var push_daily: Bool
        var push_daily_at: String
        var push_streak: Bool
        var push_passed: Bool
    }

    private struct StoredSeed: Encodable {
        var puzzleDate: String
        var tries: Int
        var solved: Bool
        var elapsedMs: Int
        var score: Int
        var attempts: [Attempt]
        var elapsedSource: String
        var submittedAt: String
    }

    private struct SubmitSeed: Encodable {
        var result: StoredSeed
        var streak: Int
    }

    private struct RegisterSeed: Encodable {
        var userId: String
        var displayName: String
        var inviteCode: String
        var existing: Bool
    }

    private struct MatchedSeed: Encodable {
        var userId: String
        var displayName: String
        var hash: String
    }

    private struct FriendSeed: Encodable {
        var userId: String
        var displayName: String
    }

    private struct MatchSeed: Encodable {
        var matches: [MatchedSeed]
        var friends: [FriendSeed]
        var stored: Int
    }

    private struct SummarySeed: Encodable {
        var puzzle_date: String
        var tries: Int
        var solved: Bool
        var score: Int
    }

    /// Encodes a seed and decodes it as the real KithCore type. Optional seed fields are
    /// omitted by the synthesized encoder and read back with `decodeIfPresent`, so a nil
    /// `rank` stays nil rather than becoming a null the decoder rejects.
    private static func convert<Seed: Encodable, Wire: Decodable>(_ seed: Seed, to: Wire.Type) throws -> Wire {
        let data: Data
        do {
            data = try JSONEncoder().encode(seed)
        } catch {
            throw KithError.decoding(String(describing: error))
        }
        do {
            return try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw KithError.decoding(String(describing: error))
        }
    }

    // MARK: - Mutable state (all of it behind `lock`)

    private let lock = NSLock()

    private let state: State
    private var recordedCalls: [String] = []
    private var shouldFailNextSubmit = false

    private var registered: Bool
    private var profileSeed: ProfileSeed
    private var storedResults: [String: StoredSeed] = [:]
    private var history: [SummarySeed] = []
    private var circleSeeds: [CircleSeed] = []
    private var reactionSeeds: [ReactionSeed] = []
    private var tauntSeeds: [TauntSeed] = []
    private var streakValue: Int
    private var createdCircleCount = 0

    // Games hub state, keyed `"<date>#<game>"`.
    private var startedGames: Set<String> = []
    private var storedGames: [String: StoredGameSeed] = [:]
    private var recordedGameSubmissions: [GameSubmission] = []
    private var shouldFailNextGameSubmit = false
    /// Mirrors the real `submit-game`'s 409 `no_start` (backend round: the caller never
    /// called `start_game` for this date/game).
    private var shouldFailNextGameSubmitWithNoStart = false

    init(state: State = .fresh) {
        self.state = state
        self.registered = state != .fresh
        self.streakValue = state == .fresh ? 0 : 12
        self.profileSeed = ProfileSeed(
            id: Self.meId,
            display_name: Self.meName,
            tz: Self.meTimeZone,
            discoverable: true,
            invite_code: Self.meInviteCode,
            push_daily: true,
            push_daily_at: "08:00:00",
            push_streak: true,
            push_passed: false
        )

        let today = Self.todayDate()

        if state != .fresh {
            // 20 days ending yesterday, tries cycling 1 / 2 / 3, for the heatmap.
            history = (1...20).reversed().map { offset in
                let tries = ((20 - offset) % 3) + 1
                return SummarySeed(
                    puzzle_date: LocalDay.shift(today, by: -offset),
                    tries: tries,
                    solved: true,
                    score: Scoring.score(tries: tries, solved: true, elapsedMs: 45_000)
                )
            }
            // Sam's taunt is visible on the friends board.
            tauntSeeds = [TauntSeed(user_id: "u-sam", puzzle_date: today, text: "took me 40 seconds")]
        }

        if state == .played {
            // 700 − 2 × 90 = 520, so the score in TESTING.md is what `Scoring` recomputes.
            storedResults[today] = StoredSeed(
                puzzleDate: today,
                tries: 2,
                solved: true,
                elapsedMs: 90_000,
                score: Scoring.score(tries: 2, solved: true, elapsedMs: 90_000),
                attempts: Self.solvedAttempts(tries: 2, elapsedMs: 90_000),
                elapsedSource: "client",
                submittedAt: Self.timestamp()
            )
            reactionSeeds = [
                // Sam reacted to me (what the board renders) …
                ReactionSeed(from_user: "u-sam", to_user: Self.meId, puzzle_date: today, emoji: "🔥"),
                // … and I reacted to Sam, which is the row `react(to:emoji:)` has to clear
                // before upserting a different emoji (TESTING.md §4.7).
                ReactionSeed(from_user: Self.meId, to_user: "u-sam", puzzle_date: today, emoji: "🔥"),
            ]
        }
    }

    // MARK: - Inspection

    /// Every call made, in order, as `"<method>(<key args>)"`.
    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    /// Makes the next `submitResult` throw `KithError.network("offline")`, once.
    var failNextSubmit: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return shouldFailNextSubmit
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            shouldFailNextSubmit = newValue
        }
    }

    // MARK: - Edge functions

    func register(displayName: String, tz: String) async throws -> RegisterResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("register(\(displayName))")
        let existing = registered
        registered = true
        profileSeed.display_name = displayName
        profileSeed.tz = tz
        return try Self.convert(
            RegisterSeed(
                userId: Self.meId,
                displayName: displayName,
                inviteCode: Self.meInviteCode,
                existing: existing
            ),
            to: RegisterResponse.self
        )
    }

    func submitResult(puzzleDate: String, tz: String, attempts: [Attempt]) async throws -> SubmitResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("submitResult")

        if shouldFailNextSubmit {
            shouldFailNextSubmit = false
            throw KithError.network("offline")
        }
        if storedResults[puzzleDate] != nil {
            throw KithError.api(status: 409, code: "already_played",
                                message: "You've already played today.")
        }
        guard let last = attempts.last else {
            throw KithError.api(status: 400, code: "bad_attempts", message: "No attempts.")
        }

        // The server never trusts the client's feedback: recompute it, and the score, from
        // the submitted orders alone.
        let recomputed = attempts.map { attempt in
            Attempt(
                order: attempt.order,
                feedback: LineupEngine.feedback(for: attempt.order, correctOrder: Self.correctOrder),
                elapsedMs: attempt.elapsedMs
            )
        }
        let solved = recomputed.last?.isSolved ?? false
        let tries = recomputed.count
        let seed = StoredSeed(
            puzzleDate: puzzleDate,
            tries: tries,
            solved: solved,
            elapsedMs: last.elapsedMs,
            score: Scoring.score(tries: tries, solved: solved, elapsedMs: last.elapsedMs),
            attempts: recomputed,
            elapsedSource: "client",
            submittedAt: Self.timestamp()
        )
        storedResults[puzzleDate] = seed
        streakValue += 1
        return try Self.convert(SubmitSeed(result: seed, streak: streakValue), to: SubmitResponse.self)
    }

    func matchContacts(added: [String], removed: [String], full: Bool) async throws -> MatchResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("matchContacts(added:\(added.count),removed:\(removed.count),full:\(full))")

        let people = [("u-mum", "Mum"), ("u-sam", "Sam"), ("u-dev", "Dev")]
        let matched = zip(added.prefix(people.count), people).map { hash, person in
            MatchedSeed(userId: person.0, displayName: person.1, hash: hash)
        }
        return try Self.convert(
            MatchSeed(
                matches: matched,
                friends: matched.map { FriendSeed(userId: $0.userId, displayName: $0.displayName) },
                stored: added.count
            ),
            to: MatchResponse.self
        )
    }

    func deleteAccount() async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("deleteAccount")
        registered = false
        storedResults = [:]
        startedGames = []
        storedGames = [:]
        recordedGameSubmissions = []
        history = []
        circleSeeds = []
        reactionSeeds = []
        tauntSeeds = []
        streakValue = 0
    }

    // MARK: - RPCs

    func startPuzzle(date: String) async throws -> Puzzle {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("startPuzzle")
        // The date the client asked for, so the engine's `YYYY-MM-DD` check and
        // `AppModel.today` always agree, even across a midnight flip.
        return Self.puzzle(for: date)
    }

    /// The five-argument `board` is the protocol requirement (docs/07); the four-argument
    /// spelling every pre-games call site uses comes from `KithAPI`'s extension.
    func board(kind: BoardKind, scopeId: String?, period: BoardPeriod, date: String,
               game: BoardGame) async throws -> [BoardRow] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("board(\(kind.rawValue),\(period.rawValue),\(game.rawValue))")
        switch kind {
        case .friends:
            return try Self.convert(friendRowSeeds(game: game, on: date), to: [BoardRow].self)
        case .everyone:
            return try Self.convert(Self.everyoneRowSeeds(), to: [BoardRow].self)
        case .circle:
            guard circleSeeds.contains(where: { $0.id == (scopeId ?? Self.circleId) }) else { return [] }
            return try Self.convert(circleRowSeeds(game: game, on: date), to: [BoardRow].self)
        }
    }

    func joinCircle(code: String) async throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let cleaned = Self.normalize(code)
        recordedCalls.append("joinCircle(\(cleaned))")
        guard cleaned == Self.circleCode else {
            throw KithError.api(status: 404, code: "no_circle", message: "That code doesn't match a circle.")
        }
        if !circleSeeds.contains(where: { $0.code == Self.circleCode }) {
            circleSeeds.append(CircleSeed(
                id: Self.circleId,
                code: Self.circleCode,
                name: Self.circleName,
                owner_id: Self.circleOwner
            ))
        }
        return Self.circleId
    }

    func myStreak() async throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("myStreak")
        return streakValue
    }

    func track(_ name: String, props: [String: String]) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("track(\(name))")
    }

    func hideTaunt(author: String, date: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("hideTaunt(\(author))")
        tauntSeeds.removeAll { $0.user_id == author && $0.puzzle_date == date }
    }

    // MARK: - Tables

    func profile() async throws -> Profile {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("profile")
        guard registered else {
            throw KithError.api(status: 406, code: "PGRST116", message: "no rows returned")
        }
        return try Self.convert(profileSeed, to: Profile.self)
    }

    func updateProfile(_ patch: ProfilePatch) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("updateProfile(\(Self.describe(patch)))")
        if let value = patch.display_name { profileSeed.display_name = value }
        if let value = patch.tz { profileSeed.tz = value }
        if let value = patch.discoverable { profileSeed.discoverable = value }
        if let value = patch.push_daily { profileSeed.push_daily = value }
        if let value = patch.push_daily_at { profileSeed.push_daily_at = value }
        if let value = patch.push_streak { profileSeed.push_streak = value }
        if let value = patch.push_passed { profileSeed.push_passed = value }
    }

    func myCircles() async throws -> [Circle] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("myCircles")
        return try Self.convert(circleSeeds, to: [Circle].self)
    }

    func createCircle(name: String) async throws -> Circle {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("createCircle(\(name))")
        createdCircleCount += 1
        let seed = CircleSeed(
            id: "c-new-\(createdCircleCount)",
            code: "NEW\(String(format: "%03d", createdCircleCount))",
            name: name,
            owner_id: Self.meId
        )
        circleSeeds.append(seed)
        return try Self.convert(seed, to: Circle.self)
    }

    func leaveCircle(id: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("leaveCircle(\(id))")
        circleSeeds.removeAll { $0.id == id }
    }

    func reactions(date: String) async throws -> [Reaction] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("reactions")
        return try Self.convert(reactionSeeds.filter { $0.puzzle_date == date }, to: [Reaction].self)
    }

    func react(to userId: String, date: String, emoji: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("react(\(userId),\(emoji))")
        reactionSeeds.removeAll { $0.from_user == Self.meId && $0.to_user == userId && $0.puzzle_date == date }
        reactionSeeds.append(ReactionSeed(from_user: Self.meId, to_user: userId, puzzle_date: date, emoji: emoji))
    }

    func unreact(to userId: String, date: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("unreact(\(userId))")
        reactionSeeds.removeAll { $0.from_user == Self.meId && $0.to_user == userId && $0.puzzle_date == date }
    }

    func taunts(date: String) async throws -> [Taunt] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("taunts")
        return try Self.convert(tauntSeeds.filter { $0.puzzle_date == date }, to: [Taunt].self)
    }

    func setTaunt(date: String, text: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("setTaunt")
        guard !tauntSeeds.contains(where: { $0.user_id == Self.meId && $0.puzzle_date == date }) else {
            throw KithError.api(status: 409, code: "already_taunted", message: "One a day.")
        }
        tauntSeeds.append(TauntSeed(user_id: Self.meId, puzzle_date: date, text: text))
    }

    func myResults(sinceDate: String) async throws -> [ResultSummary] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("myResults")
        var seeds = history
        for stored in storedResults.values {
            seeds.append(SummarySeed(
                puzzle_date: stored.puzzleDate,
                tries: stored.tries,
                solved: stored.solved,
                score: stored.score
            ))
        }
        let filtered = seeds
            .filter { $0.puzzle_date >= sinceDate }
            .sorted { $0.puzzle_date < $1.puzzle_date }
        return try Self.convert(filtered, to: [ResultSummary].self)
    }

    func registerDevice(apnsToken: String, env: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("registerDevice(\(env))")
    }

    func reveal(itemIds: [Int]) async throws -> [RevealItem] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("reveal")
        let byId = Dictionary(Self.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return itemIds.compactMap { id in
            guard let item = byId[id] else { return nil }
            return RevealItem(id: item.id, label: item.label, value: item.value, fact: item.fact)
        }
    }

    // MARK: - Games hub (docs/07, PLAN-games.md)

    /// Stars 5×5. Stars sit at columns `[1, 3, 0, 2, 4]` (row by row) and the regions are
    /// simply the five rows — the smallest connected partition in which region *r* holds its
    /// own star, which is all the UI test needs. No two stars touch:
    /// (0,1) (1,3) (2,0) (3,2) (4,4).
    static let starsSolution = [1, 3, 0, 2, 4]

    static func starsSpec() -> StarsSpec {
        let n = starsSolution.count
        let regions = (0..<n).map { row in Array(repeating: row, count: n) }
        return StarsSpec(n: n, regions: regions)
    }

    /// Duo 6×6. A genuine Tango solution: every row and column holds three of each symbol
    /// and no three consecutive cells match. All 30 off-diagonal cells are given, so a test
    /// fills exactly the six cells on the leading diagonal.
    static let duoSolution: [[Int]] = [
        [0, 0, 1, 1, 0, 1],
        [0, 1, 0, 0, 1, 1],
        [1, 0, 0, 1, 1, 0],
        [0, 1, 1, 0, 0, 1],
        [1, 1, 0, 1, 0, 0],
        [1, 0, 1, 0, 1, 0],
    ]

    /// The six cells left blank, in row order: the leading diagonal.
    static var duoBlanks: [GridPoint] { (0..<6).map { GridPoint(row: $0, col: $0) } }

    static func duoSpec() -> DuoSpec {
        let blanks = Set(duoBlanks)
        let givens: [[Int?]] = (0..<6).map { row in
            (0..<6).map { column in
                blanks.contains(GridPoint(row: row, col: column)) ? nil : duoSolution[row][column]
            }
        }
        // Two constraints, each touching a blank cell so the badges are not decorative:
        // (0,0) == (0,1) (both ●) and (1,0) ≠ (1,1) (● then ○).
        return DuoSpec(n: 6, givens: givens, eq: [[0, 0, 0, 1]], ne: [[1, 0, 1, 1]])
    }

    /// Trail 3×3 with waypoints 1→3 on the diagonal, solved by the snake
    /// (0,0) (0,1) (0,2) (1,2) (1,1) (1,0) (2,0) (2,1) (2,2).
    static let trailPath: [[Int]] = [[0, 0], [0, 1], [0, 2], [1, 2], [1, 1], [1, 0], [2, 0], [2, 1], [2, 2]]

    static func trailSpec() -> TrailSpec {
        TrailSpec(n: 3, waypoints: [[0, 0], [1, 1], [2, 2]])
    }

    /// Quint's answer (docs/07 §Quint, TESTING.md §3): "crane". `slate` then `crane` is the
    /// two-guess solve `GamesTests`/`GamesUITests` drive.
    static let quintAnswer = "crane"

    static func quintSpec() -> QuintSpec {
        QuintSpec(answer: quintAnswer)
    }

    static func spec(for game: GameKind) -> GameSpec {
        switch game {
        case .stars: return .stars(starsSpec())
        case .duo: return .duo(duoSpec())
        case .trail: return .trail(trailSpec())
        case .quint: return .quint(quintSpec())
        }
    }

    /// Puzzle numbers, so `GameShareText` renders something stable.
    static func number(for game: GameKind) -> Int {
        switch game {
        case .stars: return 12
        case .duo: return 13
        case .trail: return 14
        case .quint: return 3
        }
    }

    private struct DailyGameSeed: Encodable {
        var date: String
        var game: GameKind
        var number: Int
        var difficulty: String
    }

    private struct GameResultSeed: Encodable {
        var date: String
        var game: GameKind
        var elapsed_ms: Int
        var mistakes: Int
        var solved: Bool
        var gave_up: Bool
        var score: Int
    }

    private struct StoredGameSeed: Encodable {
        var date: String
        var game: GameKind
        var elapsedMs: Int
        var elapsedSource: String
        var mistakes: Int
        var solved: Bool
        var gaveUp: Bool
        var score: Int
        var submittedAt: String
    }

    private struct SubmitGameSeed: Encodable {
        var result: StoredGameSeed
        var streak: Int
    }

    /// Every `submitGame` the fake has seen, in order, for unit-test assertions.
    struct GameSubmission: Sendable, Equatable {
        let date: String
        let game: GameKind
        let elapsedMs: Int
        let mistakes: Int
        let gaveUp: Bool
        /// The JSON the real client would have put in the `answer` field, or nil on a give-up.
        let answerJSON: String?
    }

    var gameSubmissions: [GameSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return recordedGameSubmissions
    }

    /// Makes the next `submitGame` throw `KithError.network("offline")`, once.
    var failNextGameSubmit: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return shouldFailNextGameSubmit
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            shouldFailNextGameSubmit = newValue
        }
    }

    /// Makes the next `submitGame` throw the same `KithError.api(status: 409, code:
    /// "no_start", …)` the real backend does when `start_game` was never called for that
    /// date/game — the grid-game twin of `already_played` detection above, and what
    /// `AppModel.submitGame`'s no-start retry is exercised against.
    var failNextGameSubmitWithNoStart: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return shouldFailNextGameSubmitWithNoStart
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            shouldFailNextGameSubmitWithNoStart = newValue
        }
    }

    func startGame(date: String, game: GameKind) async throws -> StartedGame {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("startGame(\(game.rawValue))")
        startedGames.insert(Self.gameKey(date: date, game: game))
        return StartedGame(
            date: date,
            game: game,
            number: Self.number(for: game),
            difficulty: "easy",
            spec: Self.spec(for: game)
        )
    }

    func submitGame(date: String, game: GameKind, tz: String, elapsedMs: Int, mistakes: Int,
                    gaveUp: Bool, answer: GameAnswer?) async throws -> SubmitGameResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("submitGame(\(game.rawValue),gaveUp:\(gaveUp))")

        if shouldFailNextGameSubmitWithNoStart {
            shouldFailNextGameSubmitWithNoStart = false
            throw KithError.api(status: 409, code: "no_start",
                                message: "Start the game before submitting a result.")
        }

        if shouldFailNextGameSubmit {
            shouldFailNextGameSubmit = false
            throw KithError.network("offline")
        }

        let key = Self.gameKey(date: date, game: game)
        recordedGameSubmissions.append(GameSubmission(
            date: date, game: game, elapsedMs: elapsedMs, mistakes: mistakes,
            gaveUp: gaveUp, answerJSON: Self.json(answer)
        ))

        if storedGames[key] != nil {
            throw KithError.api(status: 409, code: "already_played",
                                message: "You've already played that one today.")
        }

        // Quint (docs/07 §Quint wire formats): the server never trusts the client's own
        // `solved`/`mistakes` — both are recomputed from the submitted guesses, and a
        // give-up carries no guesses to validate.
        var solved = !gaveUp
        var storedMistakes = mistakes
        let score: Int
        if game == .quint {
            var guesses: [String] = []
            if case .quint(let submitted)? = answer { guesses = submitted }
            if !gaveUp {
                guard (1...6).contains(guesses.count), guesses.allSatisfy({ $0.count == 5 }) else {
                    throw KithError.api(status: 400, code: "bad_answer", message: "Invalid guesses.")
                }
            }
            solved = !gaveUp && guesses.last == Self.quintAnswer
            storedMistakes = guesses.filter { $0 != Self.quintAnswer }.count
            let totalGuesses = storedMistakes + (solved ? 1 : 0)
            score = GameScoring.quintScore(elapsedMs: elapsedMs, guesses: totalGuesses,
                                           solved: solved, gaveUp: gaveUp)
        } else {
            score = GameScoring.score(elapsedMs: elapsedMs, gaveUp: gaveUp)
        }

        let seed = StoredGameSeed(
            date: date,
            game: game,
            elapsedMs: elapsedMs,
            elapsedSource: startedGames.contains(key) ? "server" : "client",
            mistakes: storedMistakes,
            solved: solved,
            gaveUp: gaveUp,
            score: score,
            submittedAt: Self.timestamp()
        )
        storedGames[key] = seed
        streakValue += 1
        return try Self.convert(SubmitGameSeed(result: seed, streak: streakValue),
                                to: SubmitGameResponse.self)
    }

    func myGameResults(sinceDate: String) async throws -> [GameResultSummary] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("myGameResults")
        let seeds = storedGames.values
            .filter { $0.date >= sinceDate }
            .map { stored in
                GameResultSeed(date: stored.date, game: stored.game, elapsed_ms: stored.elapsedMs,
                               mistakes: stored.mistakes, solved: stored.solved,
                               gave_up: stored.gaveUp, score: stored.score)
            }
            .sorted { ($0.date, $0.game.rawValue) < ($1.date, $1.game.rawValue) }
        return try Self.convert(seeds, to: [GameResultSummary].self)
    }

    func dailyGames(date: String) async throws -> [DailyGameRow] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("dailyGames")
        let seeds = GameKind.allCases.map { game in
            DailyGameSeed(date: date, game: game, number: Self.number(for: game), difficulty: "easy")
        }
        return try Self.convert(seeds, to: [DailyGameRow].self)
    }

    private static func gameKey(date: String, game: GameKind) -> String {
        "\(date)#\(game.rawValue)"
    }

    /// The wire JSON for an answer (`{"stars":[…]}`, `{"cells":[[…]]}`, `{"path":[[r,c],…]}`).
    ///
    /// Deliberately NOT `JSONEncoder().encode(answer)`, even though `GameAnswer.encode(to:)`
    /// is now fully implemented in KithCore: this renders the same three shapes independently
    /// so a unit test asserting on `answerJSON` (`GamesTests`) is checking the fake's output
    /// against a hand-written expectation, not against `GameAnswer.encode` marking its own
    /// homework.
    private static func json(_ answer: GameAnswer?) -> String? {
        guard let answer else { return nil }
        func flat(_ values: [Int]) -> String {
            "[" + values.map(String.init).joined(separator: ",") + "]"
        }
        func nested(_ values: [[Int]]) -> String {
            "[" + values.map(flat).joined(separator: ",") + "]"
        }
        switch answer {
        case .stars(let columns): return "{\"stars\":\(flat(columns))}"
        case .duo(let cells): return "{\"cells\":\(nested(cells))}"
        case .trail(let path): return "{\"path\":\(nested(path))}"
        case .quint(let guesses):
            let quoted = guesses.map { "\"\($0)\"" }.joined(separator: ",")
            return "{\"guesses\":[\(quoted)]}"
        }
    }

    // MARK: - Board data (docs/07 "Boards (revised 2026-09-13)")

    /// Dispatches to the per-game fixture. Every game (Lineup included) now carries its
    /// own `solved_count` / `played_count` / `prev_*` fields, since the client ranks each
    /// section from those instead of the server's `rank`/`score`; `total` is summed from
    /// the other five rather than kept separately.
    private func friendRowSeeds(game: BoardGame, on date: String) -> [RowSeed] {
        switch game {
        case .lineup: return lineupRowSeeds(on: date)
        case .stars: return Self.starsRowSeeds()
        case .duo: return Self.duoRowSeeds()
        case .trail: return Self.trailRowSeeds()
        case .quint: return Self.quintRowSeeds()
        case .total: return totalRowSeeds(on: date)
        }
    }

    private func circleRowSeeds(game: BoardGame, on date: String) -> [RowSeed] {
        let ids: Set<String> = ["u-mum", Self.meId]
        return friendRowSeeds(game: game, on: date).filter { ids.contains($0.user_id) }
    }

    /// Mum, Sam and Dev have played; Jo has not; my row reflects whatever has been stored
    /// for today. Yesterday Sam was faster than Mum (`prev_elapsed_ms` 26 000 vs 70 000) —
    /// the reverse of today — so the client's rank-movement arrow has something to show;
    /// Dev is "new" (unplayed yesterday).
    private func lineupRowSeeds(on date: String) -> [RowSeed] {
        // Keyed off the date the client asked for, so my row reflects a submission even
        // if the device's calendar day differs from the fake's UTC one.
        let stored = storedResults[date] ?? storedResults[Self.todayDate()]
        let seeds = [
            RowSeed(user_id: "u-mum", display_name: "Mum", score: 948, tries: 1, elapsed_ms: 26_000,
                    attempts: Self.solvedAttempts(tries: 1, elapsedMs: 26_000),
                    played: true, rank: 1, prev_rank: 3,
                    solved_count: 1, played_count: 1,
                    prev_played: true, prev_elapsed_ms: 70_000,
                    prev_solved_count: 1, prev_played_count: 1),
            RowSeed(user_id: "u-sam", display_name: "Sam", score: 610, tries: 2, elapsed_ms: 45_000,
                    attempts: Self.solvedAttempts(tries: 2, elapsedMs: 45_000),
                    played: true, rank: 2, prev_rank: 1,
                    solved_count: 1, played_count: 1,
                    prev_played: true, prev_elapsed_ms: 26_000,
                    prev_solved_count: 1, prev_played_count: 1),
            RowSeed(user_id: "u-dev", display_name: "Dev", score: 160, tries: 3, elapsed_ms: 120_000,
                    attempts: Self.solvedAttempts(tries: 3, elapsedMs: 120_000),
                    played: true, rank: 3, prev_rank: nil,
                    solved_count: 1, played_count: 1,
                    prev_played: false, prev_elapsed_ms: nil,
                    prev_solved_count: 0, prev_played_count: 0),
            RowSeed(user_id: "u-jo", display_name: "Jo", score: 0, tries: nil, elapsed_ms: nil,
                    attempts: nil, played: false, rank: nil, prev_rank: nil,
                    solved_count: 0, played_count: 0,
                    prev_played: false, prev_elapsed_ms: nil,
                    prev_solved_count: 0, prev_played_count: 0),
            RowSeed(user_id: Self.meId, display_name: Self.meName, score: stored?.score ?? 0,
                    tries: stored?.tries, elapsed_ms: stored?.elapsedMs, attempts: stored?.attempts,
                    played: stored != nil, rank: stored == nil ? nil : 3, prev_rank: nil,
                    solved_count: stored != nil ? 1 : 0, played_count: stored != nil ? 1 : 0,
                    prev_played: false, prev_elapsed_ms: nil,
                    prev_solved_count: 0, prev_played_count: 0),
        ]
        // The server returns played rows first, by score descending; the client re-ranks
        // every section from `elapsed_ms`/`solved_count` regardless (docs/07), so this
        // ordering is cosmetic only.
        return seeds.filter(\.played).sorted { $0.score > $1.score } + seeds.filter { !$0.played }
    }

    /// Shared shape for Stars/Duo/Trail/Quint: Mum and Sam solve, Dev gives up today
    /// after solving yesterday (the "gave up" / "failed" row every per-game board needs),
    /// Jo and I have never played either day. `prevDev == nil` means Dev is "new" (also
    /// unplayed yesterday); Stars/Duo give Dev a `prevDev`, Trail leaves it nil, so both
    /// shapes of movement exist across the four boards. A give-up still carries a real
    /// `elapsed_ms` — the server always records how long the attempt ran before revealing
    /// the solution — since "All games" sums time over every played game, not just solved
    /// ones (finding B3).
    private static func gridGameRowSeeds(todayMum: Int, todaySam: Int, todayDev: Int,
                                         prevMum: Int, prevSam: Int, prevDev: Int?) -> [RowSeed] {
        [
            RowSeed(user_id: "u-mum", display_name: "Mum", score: 100, elapsed_ms: todayMum,
                    played: true, solved_count: 1, played_count: 1,
                    prev_played: true, prev_elapsed_ms: prevMum,
                    prev_solved_count: 1, prev_played_count: 1),
            RowSeed(user_id: "u-sam", display_name: "Sam", score: 90, elapsed_ms: todaySam,
                    played: true, solved_count: 1, played_count: 1,
                    prev_played: true, prev_elapsed_ms: prevSam,
                    prev_solved_count: 1, prev_played_count: 1),
            RowSeed(user_id: "u-dev", display_name: "Dev", score: 10, elapsed_ms: todayDev,
                    played: true, solved_count: 0, played_count: 1,
                    prev_played: prevDev != nil, prev_elapsed_ms: prevDev,
                    prev_solved_count: prevDev != nil ? 1 : 0, prev_played_count: prevDev != nil ? 1 : 0),
            RowSeed(user_id: "u-jo", display_name: "Jo", score: 0,
                    played: false, solved_count: 0, played_count: 0,
                    prev_played: false, prev_elapsed_ms: nil,
                    prev_solved_count: 0, prev_played_count: 0),
            // The fake has no per-grid-game "my" data, so I show up unplayed here even in
            // the `played` app state (unlike Lineup, whose row reflects `storedResults`).
            RowSeed(user_id: Self.meId, display_name: Self.meName, score: 0,
                    played: false, solved_count: 0, played_count: 0,
                    prev_played: false, prev_elapsed_ms: nil,
                    prev_solved_count: 0, prev_played_count: 0),
        ]
    }

    private static func starsRowSeeds() -> [RowSeed] {
        gridGameRowSeeds(todayMum: 40_000, todaySam: 55_000, todayDev: 80_000,
                         prevMum: 70_000, prevSam: 30_000, prevDev: 90_000)
    }

    private static func duoRowSeeds() -> [RowSeed] {
        gridGameRowSeeds(todayMum: 35_000, todaySam: 42_000, todayDev: 65_000,
                         prevMum: 60_000, prevSam: 20_000, prevDev: 75_000)
    }

    private static func trailRowSeeds() -> [RowSeed] {
        gridGameRowSeeds(todayMum: 50_000, todaySam: 65_000, todayDev: 95_000,
                         prevMum: 80_000, prevSam: 40_000, prevDev: nil)
    }

    private static func quintRowSeeds() -> [RowSeed] {
        gridGameRowSeeds(todayMum: 60_000, todaySam: 70_000, todayDev: 100_000,
                         prevMum: 95_000, prevSam: 50_000, prevDev: 110_000)
    }

    /// "All games": summed from the other five boards rather than kept as its own
    /// fixture, so it can never drift from them. `solved_count` is games solved today;
    /// `elapsed_ms` is total time across every *played* game today, solved or given up
    /// (docs/07 "Boards (revised 2026-09-13)": server semantics — "All games ranks by
    /// games solved today descending, then total time ascending", and that total time is
    /// every played game's time, not only the solved ones; finding B3).
    private func totalRowSeeds(on date: String) -> [RowSeed] {
        let perGame = [lineupRowSeeds(on: date), Self.starsRowSeeds(), Self.duoRowSeeds(),
                       Self.trailRowSeeds(), Self.quintRowSeeds()]
        let names: [(String, String)] = [
            ("u-mum", "Mum"), ("u-sam", "Sam"), ("u-dev", "Dev"), ("u-jo", "Jo"),
            (Self.meId, Self.meName),
        ]

        let rows: [RowSeed] = names.map { userId, name in
            var solved = 0, played = 0, elapsed = 0
            var hasElapsed = false
            var prevSolved = 0, prevPlayed = 0, prevElapsed = 0
            var hasPrevElapsed = false
            for game in perGame {
                guard let row = game.first(where: { $0.user_id == userId }) else { continue }
                if (row.solved_count ?? 0) > 0 { solved += 1 }
                if (row.played_count ?? 0) > 0 {
                    played += 1
                    if let ms = row.elapsed_ms {
                        elapsed += ms
                        hasElapsed = true
                    }
                }
                if (row.prev_solved_count ?? 0) > 0 { prevSolved += 1 }
                if (row.prev_played_count ?? 0) > 0 {
                    prevPlayed += 1
                    if let ms = row.prev_elapsed_ms {
                        prevElapsed += ms
                        hasPrevElapsed = true
                    }
                }
            }
            return RowSeed(user_id: userId, display_name: name, score: solved * 100,
                           elapsed_ms: hasElapsed ? elapsed : nil,
                           played: played > 0, solved_count: solved, played_count: played,
                           prev_played: prevPlayed > 0, prev_elapsed_ms: hasPrevElapsed ? prevElapsed : nil,
                           prev_solved_count: prevSolved, prev_played_count: prevPlayed)
        }
        return rows.filter(\.played).sorted { $0.score > $1.score } + rows.filter { !$0.played }
    }

    private static func everyoneRowSeeds() -> [RowSeed] {
        let people = [("u-e1", "Priya", 980), ("u-e2", "Marco", 905), ("u-e3", "Ada", 860),
                      ("u-e4", "Kwame", 740), ("u-e5", "Lena", 610)]
        return people.enumerated().map { index, person in
            RowSeed(user_id: person.0, display_name: person.1, score: person.2, tries: nil,
                    elapsed_ms: nil, attempts: nil, played: true, rank: index + 1, prev_rank: nil)
        }
    }

    // MARK: - Small helpers

    /// `tries` attempts whose last one is the correct order; the earlier ones are the
    /// shuffled presentation order, so the mini grids are not all green.
    private static func solvedAttempts(tries: Int, elapsedMs: Int) -> [Attempt] {
        let clamped = min(max(tries, 1), LineupEngine.maxTries)
        var attempts: [Attempt] = []
        for index in 0..<(clamped - 1) {
            let at = max(0, elapsedMs - (clamped - index) * 5_000)
            attempts.append(Attempt(
                order: presentationOrder,
                feedback: LineupEngine.feedback(for: presentationOrder, correctOrder: correctOrder),
                elapsedMs: at
            ))
        }
        attempts.append(Attempt(
            order: correctOrder,
            feedback: LineupEngine.feedback(for: correctOrder, correctOrder: correctOrder),
            elapsedMs: elapsedMs
        ))
        return attempts
    }

    /// "KITH-abc123", "kith-ABC123" and "ABC123" all name the same circle.
    private static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("KITH-") { value = String(value.dropFirst(5)) }
        return value.filter { $0.isLetter || $0.isNumber }
    }

    /// Only the non-nil fields, so a discoverable-only patch records as
    /// `updateProfile(discoverable:false)`.
    private static func describe(_ patch: ProfilePatch) -> String {
        var parts: [String] = []
        if let value = patch.display_name { parts.append("display_name:\(value)") }
        if let value = patch.tz { parts.append("tz:\(value)") }
        if let value = patch.discoverable { parts.append("discoverable:\(value)") }
        if let value = patch.last_open_at { parts.append("last_open_at:\(value)") }
        if let value = patch.push_daily { parts.append("push_daily:\(value)") }
        if let value = patch.push_daily_at { parts.append("push_daily_at:\(value)") }
        if let value = patch.push_streak { parts.append("push_streak:\(value)") }
        if let value = patch.push_passed { parts.append("push_passed:\(value)") }
        return parts.joined(separator: ",")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

#endif
