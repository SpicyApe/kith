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
        var tries: Int?
        var elapsed_ms: Int?
        var attempts: [Attempt]?
        var played: Bool
        var rank: Int?
        var prev_rank: Int?
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

    func board(kind: BoardKind, scopeId: String?, period: BoardPeriod, date: String) async throws -> [BoardRow] {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append("board(\(kind.rawValue),\(period.rawValue))")
        switch kind {
        case .friends:
            return try Self.convert(friendRowSeeds(on: date), to: [BoardRow].self)
        case .everyone:
            return try Self.convert(Self.everyoneRowSeeds(), to: [BoardRow].self)
        case .circle:
            guard circleSeeds.contains(where: { $0.id == (scopeId ?? Self.circleId) }) else { return [] }
            return try Self.convert(circleRowSeeds(on: date), to: [BoardRow].self)
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

    // MARK: - Board data

    /// Mum, Sam and Dev have played; Jo has not; my row reflects whatever has been stored
    /// for today. Four friends with three played is what `board.header` reads back as
    /// "3 of 4 friends played today" (TESTING.md §5.3).
    private func friendRowSeeds(on date: String) -> [RowSeed] {
        // Keyed off the date the client asked for, so my row reflects a submission even
        // if the device's calendar day differs from the fake's UTC one.
        let stored = storedResults[date] ?? storedResults[Self.todayDate()]
        let seeds = [
            RowSeed(user_id: "u-mum", display_name: "Mum", score: 948, tries: 1, elapsed_ms: 26_000,
                    attempts: Self.solvedAttempts(tries: 1, elapsedMs: 26_000),
                    played: true, rank: 1, prev_rank: 3),
            RowSeed(user_id: "u-sam", display_name: "Sam", score: 610, tries: 2, elapsed_ms: 45_000,
                    attempts: Self.solvedAttempts(tries: 2, elapsedMs: 45_000),
                    played: true, rank: 2, prev_rank: 1),
            RowSeed(user_id: "u-dev", display_name: "Dev", score: 160, tries: 3, elapsed_ms: 120_000,
                    attempts: Self.solvedAttempts(tries: 3, elapsedMs: 120_000),
                    played: true, rank: 3, prev_rank: nil),
            RowSeed(user_id: "u-jo", display_name: "Jo", score: 0, tries: nil, elapsed_ms: nil,
                    attempts: nil, played: false, rank: nil, prev_rank: nil),
            RowSeed(user_id: Self.meId, display_name: Self.meName, score: stored?.score ?? 0,
                    tries: stored?.tries, elapsed_ms: stored?.elapsedMs, attempts: stored?.attempts,
                    played: stored != nil, rank: stored == nil ? nil : 3, prev_rank: nil),
        ]
        // The server returns played rows first, by score descending.
        return seeds.filter(\.played).sorted { $0.score > $1.score } + seeds.filter { !$0.played }
    }

    private func circleRowSeeds(on date: String) -> [RowSeed] {
        let ids: Set<String> = ["u-mum", Self.meId]
        return friendRowSeeds(on: date).filter { ids.contains($0.user_id) }
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
