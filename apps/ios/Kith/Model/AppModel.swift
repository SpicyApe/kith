// AppModel.swift — the single observable object the whole app reads.
//
// Rules (apps/ios/PLAN.md): no logic here that belongs in KithCore, every network
// call goes through `KithAPI`, the engine is a value type mutated through methods so
// SwiftUI sees the change.

import Foundation
import GridGames
import KithCore
import LineupEngine
import Observation

// MARK: - Small value types the views read

struct ToastMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    /// Coral background instead of the neutral one.
    var isError: Bool = false
}

enum AppTab: String, Hashable, Sendable, CaseIterable {
    case today, board, circles, you
}

/// Stage of the app shell.
enum AppStage: Equatable, Sendable {
    case launching
    /// No Supabase session at all.
    case signedOut
    /// Signed in but no `users` row yet — onboarding resumes at the name step.
    case registering
    case ready
}

/// The two post-play onboarding screens from docs/02 §6 steps 7 and 8.
/// `OnboardingFlow` (KithCore) has no states for them, so the tail is tracked here.
enum OnboardingTail: Equatable, Sendable {
    case none
    case friendsFound
    case notifications
}

struct BoardCacheKey: Hashable, Sendable {
    let kind: BoardKind
    let scopeId: String?
    let period: BoardPeriod
    let date: String
    /// Which column the board was asked for (docs/07). Defaults to Lineup so every call
    /// site written before the games hub still compiles and still means the same thing.
    let game: BoardGame

    init(kind: BoardKind, scopeId: String?, period: BoardPeriod, date: String,
         game: BoardGame = .lineup) {
        self.kind = kind
        self.scopeId = scopeId
        self.period = period
        self.date = date
        self.game = game
    }
}

/// One row of the games hub (PLAN-games.md "Screens"). `Lineup` is not a `GameKind`,
/// so the hub's four rows are modelled here rather than in `GridGames`.
enum HubGame: Hashable, Sendable, CaseIterable {
    case lineup
    case grid(GameKind)

    static var allCases: [HubGame] { [.lineup] + GameKind.allCases.map(HubGame.grid) }

    var title: String {
        switch self {
        case .lineup: return "Lineup"
        case .grid(let kind): return kind.title
        }
    }

    var symbolName: String {
        switch self {
        case .lineup: return "square.stack.3d.up"
        case .grid(let kind): return kind.symbolName
        }
    }

    /// The `hub.row.<name>` identifier suffix and the analytics name.
    var slug: String {
        switch self {
        case .lineup: return "lineup"
        case .grid(let kind): return kind.rawValue
        }
    }

    var boardGame: BoardGame {
        switch self {
        case .lineup: return .lineup
        case .grid(.stars): return .stars
        case .grid(.duo): return .duo
        case .grid(.trail): return .trail
        case .grid(.quint): return .quint
        }
    }
}

// MARK: - The model

@MainActor
@Observable
final class AppModel {
    // Dependencies
    let auth: any AuthProviding
    let api: any KithAPI
    private let store: FileStore
    private let midnight = MidnightTimer()

    // Shell
    var stage: AppStage = .launching
    var tab: AppTab = .today
    var isBusy = false
    var errorMessage: String?
    var toast: ToastMessage?
    /// Last error shown as a toast; never cleared. Surfaced by the UI-testing status element.
    var lastErrorMessage: String?

    // Identity
    var profile: Profile?
    var myUserId: String = ""
    var tz: String = TimeZone.current.identifier
    var today: String = ""

    // Puzzle
    var puzzle: Puzzle?
    var engine: LineupEngine?
    var revealedAt: Date?
    var localResult: PuzzleResult?
    var storedResult: StoredResult?
    var playedToday = false
    var streak = 0
    var showResults = false
    var shareCompleted = false
    var tauntDraft = ""
    /// Taunts are write-once per day; once the server has one the field is read-only.
    var tauntSaved = false
    var resultPendingSync = false
    /// Values and facts for today's five items, in correct order. Empty until played.
    var reveal: [RevealItem] = []

    // Games hub (docs/07, PLAN-games.md)
    /// Today's `daily_games` rows. A game with no row here is not available today.
    var dailyGames: [DailyGameRow] = []
    /// Every grid-game result the hub and profile know about, keyed `"<date>#<game>"`.
    var gameResults: [String: StoredGameResult] = [:]
    /// The raw history behind the profile's per-game breakdown and the heatmap merge.
    var myGameResults: [GameResultSummary] = []
    /// Every grid game with an in-progress (or just-finished, not yet cleared) session,
    /// keyed by kind. A dictionary rather than a single slot so opening Duo does not
    /// silently discard an unfinished Stars round (reviewer finding A1).
    var activeGames: [GameKind: ActiveGame] = [:]
    /// Which kind `startGame` most recently opened. Backs the `activeGame` convenience
    /// accessor below for call sites (the three grid views, the results screen) that
    /// only ever care about "whichever game is currently on screen".
    var openGameKind: GameKind?
    /// The message from the most recent failed `startGame`, per kind, so `GameHostView`
    /// can show a "Try again" state instead of spinning forever (finding B1).
    var activeGameErrors: [GameKind: String] = [:]
    /// Drives `GameResultsView` as a cover over `GameHostView`.
    var showGameResults = false
    /// True while at least one grid-game submission is sitting in the offline queue.
    var gamePendingSync = false

    /// The game `openGameKind` points at, if any. Every internal mutator (`resetGame`,
    /// `applyMove`, `finishGame`, `giveUpGame`, `submit`) reads and writes through this
    /// rather than taking a `kind` parameter, since only one grid game is ever being
    /// interacted with at a time; `GameHostView` and its children read `activeGames[kind]`
    /// directly instead, so a screen never appears to show a different kind's session.
    var activeGame: ActiveGame? {
        get { openGameKind.flatMap { activeGames[$0] } }
        set {
            guard let kind = openGameKind else { return }
            activeGames[kind] = newValue
        }
    }

    // Social
    var boards: [BoardCacheKey: [BoardRow]] = [:]
    /// Boards whose last load failed. A cached `[]` for one of these is "we don't know",
    /// not "nobody played", so the next visit retries instead of returning the empty cache.
    var failedBoards: Set<BoardCacheKey> = []
    var taunts: [Taunt] = []
    var reactions: [Reaction] = []
    var circles: [Circle] = []
    var selectedCircleId: String?
    var myResults: [ResultSummary] = []

    // Contacts
    var directory = ContactDirectory()
    var friends: [Friend] = []
    var friendNames: [String: String] = [:]
    var lastSyncedHashes: Set<String>?
    var lastContactSync: Date?
    var contactsState: ContactsAuthState = .notDetermined
    var sharedContactCount = 0
    var isSyncingContacts = false
    /// The one-time second run at the contacts pre-prompt (see `maybeReaskForContacts`).
    var showContactsReask = false

    // Onboarding
    var onboarding = OnboardingFlow()
    var tail: OnboardingTail = .none
    var phoneDraft = ""
    var codeDraft = ""
    var nameDraft = ""
    var resendAvailableAt: Date?
    var notificationTime = "08:00"

    // Sheets / routing
    var pendingJoinCode: String?
    var showJoinSheet = false
    var showCreateCircleSheet = false
    var showDeleteConfirm = false

    // MARK: Init

    init(auth: any AuthProviding, api: any KithAPI, store: FileStore = .shared) {
        self.auth = auth
        self.api = api
        self.store = store
        self.today = LocalDay.date(Date(), tz: TimeZone.current.identifier)
    }

    convenience init() {
        let auth = AuthSession(url: AppConfig.supabaseURL, anonKey: AppConfig.supabaseAnonKey)
        let api = SupabaseKithAPI(
            baseURL: AppConfig.supabaseURL,
            anonKey: AppConfig.supabaseAnonKey,
            http: URLSessionHTTPClient(),
            auth: auth
        )
        self.init(auth: auth, api: api)
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        stage = .launching
        tz = TimeZone.current.identifier
        today = LocalDay.date(Date(), tz: tz)
        loadCaches()
        contactsState = ContactsService.authorizationState()

        startMidnightTimer()
        wirePush()

        let token: String? = (try? await auth.accessToken()) ?? nil
        guard token != nil else {
            stage = .signedOut
            onboarding = OnboardingFlow()
            return
        }
        myUserId = await auth.currentUserId() ?? ""

        do {
            let loaded = try await api.profile()
            profile = loaded
            myUserId = loaded.id
            nameDraft = loaded.display_name
            stage = .ready
        } catch {
            if isNotRegistered(error) {
                onboarding = Self.flowAtName()
                stage = .registering
                return
            }
            // Network trouble with a valid session: carry on with cached state.
            stage = .ready
            show(toast: "Offline. Showing what we have.", isError: false)
        }

        await loadToday()
        await refreshBoard(kind: .friends, scopeId: nil, period: .today)
        await retryQueuedResult()
        await retryQueuedGames()
    }

    private func loadCaches() {
        directory = store.load(ContactDirectory.self, key: StoreKey.directory) ?? ContactDirectory()
        if let hashes = store.load([String].self, key: StoreKey.syncedHashes) {
            lastSyncedHashes = Set(hashes)
        }
        lastContactSync = store.load(Timestamp.self, key: StoreKey.lastContactSync)?.value
        friendNames = store.load([String: String].self, key: StoreKey.friendNames) ?? [:]
        if let cached = store.load(Puzzle.self, key: StoreKey.cachedPuzzle), cached.date == today {
            puzzle = cached
        }
        if let result = store.load(PuzzleResult.self, key: StoreKey.localResult), result.puzzleDate == today {
            localResult = result
        }
        shareCompleted = false
    }

    /// `OnboardingFlow.step` is `private(set)` and only moves through `apply`, so the
    /// "already signed in, not registered" entry point replays the first two events.
    private static func flowAtName() -> OnboardingFlow {
        var flow = OnboardingFlow()
        flow.apply(.phoneEntered(""))
        flow.apply(.codeVerified)
        return flow
    }

    private func isNotRegistered(_ error: Error) -> Bool {
        guard let error = error as? KithError else { return false }
        if case .api(let status, let code, _) = error {
            return status == 404 || status == 406 || code == "PGRST116" || code == "not_registered"
        }
        return false
    }

    // MARK: - Today

    /// Order matters: profile → results-for-today → puzzle → friends board.
    func loadToday() async {
        today = LocalDay.date(Date(), tz: tz)

        do {
            let results = try await api.myResults(sinceDate: LocalDay.shift(today, by: -63))
            myResults = results
            playedToday = results.contains { $0.puzzle_date == today }
        } catch {
            playedToday = localResult != nil
        }

        if !(playedToday && puzzle != nil) {
            do {
                let fetched = try await api.startPuzzle(date: today)
                puzzle = fetched
                store.save(fetched, key: StoreKey.cachedPuzzle)
            } catch {
                if puzzle == nil {
                    show(toast: "Offline. No puzzle cached for today.", isError: true)
                }
            }
        }

        // A reload while a round is in progress (pull-to-refresh, a returning-user
        // profile fetch) must not throw away the player's tiles or restart the timer,
        // so an engine that is still `.playing` is left exactly as it is.
        if engine?.phase != .playing {
            if !playedToday, let puzzle {
                do {
                    engine = try LineupEngine(puzzle: puzzle)
                    revealedAt = Date()
                } catch {
                    engine = nil
                    errorMessage = "Today's puzzle looks malformed. Try again later."
                }
            } else {
                engine = nil
            }
        }

        if let streakValue = try? await api.myStreak() {
            streak = streakValue
        }

        if playedToday {
            await loadReveal()
        }

        // Best effort: the hub still renders its Lineup row when either of these fails.
        await loadGames()

        maybeReaskForContacts()
    }

    /// Today's `daily_games` rows plus the caller's grid-game history. Never throws: the
    /// hub degrades to "Not available today" rows rather than an error screen (PLAN-games.md).
    func loadGames() async {
        if let rows = try? await api.dailyGames(date: today) {
            dailyGames = rows
        }
        await refreshGameResults()
    }

    func refreshGameResults() async {
        guard let results = try? await api.myGameResults(sinceDate: LocalDay.shift(today, by: -63))
        else { return }
        myGameResults = results
        var map = gameResults
        for summary in results {
            guard let stored = Self.stored(from: summary) else { continue }
            map[Self.gameKey(date: summary.date, game: summary.game)] = stored
        }
        gameResults = map
    }

    /// Values and one-line facts for today's five items. RLS only lets this through once
    /// the caller has played, so it runs after a submit or when today is already done.
    func loadReveal() async {
        guard playedToday, reveal.isEmpty, let puzzle else { return }
        reveal = (try? await api.reveal(itemIds: puzzle.correctOrder)) ?? []
    }

    /// docs/02 §2: someone who skipped contacts at onboarding but kept playing gets one
    /// second chance at the pre-prompt, never more. The flag is persisted so it survives
    /// relaunches; `Timestamp` is reused as the box because `FileStore` round-trips a
    /// top-level JSON fragment poorly (see Persistence.swift).
    private func maybeReaskForContacts() {
        guard myResults.count >= 3,
              contactsState == .notDetermined,
              store.load(Timestamp.self, key: StoreKey.contactsReasked) == nil
        else { return }
        store.save(Timestamp(Date()), key: StoreKey.contactsReasked)
        showContactsReask = true
    }

    func onForeground() async {
        let newToday = LocalDay.date(Date(), tz: tz)
        if newToday != today {
            await rollOverToNewDay()
        }
        midnight.reschedule(tz: tz)
        await retryQueuedResult()
        await retryQueuedGames()
        contactsState = ContactsService.authorizationState()
        if shouldAutoSyncContacts {
            await syncContacts(userInitiated: false)
        }
        // The server uses `tz` to decide when to send the daily push, so a traveller's
        // timezone rides along with every "I'm back" ping.
        _ = try? await api.updateProfile(
            ProfilePatch(tz: tz, last_open_at: ISO8601DateFormatter().string(from: Date()))
        )
    }

    private var shouldAutoSyncContacts: Bool {
        guard contactsState.allowsFetch else { return false }
        guard let last = lastContactSync else { return true }
        return Date().timeIntervalSince(last) > 24 * 60 * 60
    }

    func rollOverToNewDay() async {
        today = LocalDay.date(Date(), tz: tz)
        puzzle = nil
        engine = nil
        revealedAt = nil
        localResult = nil
        storedResult = nil
        playedToday = false
        showResults = false
        shareCompleted = false
        tauntDraft = ""
        tauntSaved = false
        resultPendingSync = false
        reveal = []
        taunts = []
        reactions = []
        boards = [:]
        failedBoards = []
        dailyGames = []
        activeGames = [:]
        openGameKind = nil
        activeGameErrors = [:]
        showGameResults = false
        store.remove(key: StoreKey.cachedPuzzle)
        store.remove(key: StoreKey.localResult)
        await loadToday()
        await refreshBoard(kind: .friends, scopeId: nil, period: .today)
    }

    private func startMidnightTimer() {
        midnight.start(tz: tz) { [weak self] in
            guard let self else { return }
            Task { await self.applyMidnight() }
        }
    }

    /// What the midnight timer runs. Named separately from `rollOverToNewDay` so tests
    /// can drive the flip without waiting on a real timer (TESTING.md §4.14).
    func applyMidnight() async {
        await rollOverToNewDay()
    }

    /// The one offline submission waiting to be replayed, read straight off disk.
    /// `store` is private, so this is the seam `KithTests` uses instead of guessing the
    /// file path (TESTING.md §4.5).
    var queuedResult: QueuedResult? {
        store.load(QueuedResult.self, key: StoreKey.queuedResult)
    }

    /// Directory `store` writes into, so a test can assert the queue file really landed.
    var storeRoot: URL { store.root }

    // MARK: - Playing

    var elapsedMs: Int {
        guard let revealedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(revealedAt) * 1000))
    }

    func move(from: Int, to: Int) {
        guard var engine = self.engine else { return }
        do {
            try engine.move(from: from, to: to)
        } catch {
            return
        }
        self.engine = engine
    }

    /// SwiftUI's `.onMove` hands over an `IndexSet` and a destination in "insert before"
    /// coordinates; the engine wants a plain from/to.
    func moveRows(from source: IndexSet, to destination: Int) {
        guard let first = source.first, let engine = self.engine else { return }
        let target = destination > first ? destination - 1 : destination
        guard target != first else { return }
        // A locked tile can never be displaced. SwiftUI can still hand over a drop that
        // lands on one (the gap above a locked row), so slide to the nearest unlocked
        // slot rather than letting the engine reject the move.
        let unlocked = (0..<LineupEngine.tileCount).filter { !engine.lockedPositions.contains($0) }
        let to = unlocked.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
        move(from: first, to: to)
    }

    /// Returns the attempt just made, so the view can fire the right haptic.
    @discardableResult
    func lockIn() async -> Attempt? {
        guard var engine = self.engine, engine.phase == .playing else { return nil }
        let elapsed = elapsedMs
        let attempt: Attempt
        do {
            attempt = try engine.submit(elapsedMs: elapsed)
        } catch {
            return nil
        }
        self.engine = engine

        guard let result = engine.result else { return attempt }

        localResult = result
        store.save(result, key: StoreKey.localResult)
        playedToday = true
        await finish(result)
        return attempt
    }

    private func finish(_ result: PuzzleResult) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await api.submitResult(
                puzzleDate: result.puzzleDate,
                tz: tz,
                attempts: result.attempts
            )
            storedResult = response.result
            streak = response.streak
            resultPendingSync = false
            store.remove(key: StoreKey.queuedResult)
        } catch let error as KithError {
            if case .api(_, let code, _) = error, code == "already_played" {
                // The server already has this date. Treat it as a success and refetch.
                resultPendingSync = false
                store.remove(key: StoreKey.queuedResult)
                await refetchTodayResult()
            } else {
                queue(result)
            }
        } catch {
            queue(result)
        }

        await refreshBoard(kind: .friends, scopeId: nil, period: .today, force: true)
        await loadReveal()
        // Event names are a fixed server-side list; "result_submitted" is not on it.
        _ = try? await api.track("puzzle_submit", props: ["date": result.puzzleDate])
    }

    private func queue(_ result: PuzzleResult) {
        resultPendingSync = true
        store.save(
            QueuedResult(puzzleDate: result.puzzleDate, tz: tz, attempts: result.attempts),
            key: StoreKey.queuedResult
        )
        show(toast: "Offline. Your score will sync.", isError: false)
    }

    func retryQueuedResult() async {
        guard let queued = store.load(QueuedResult.self, key: StoreKey.queuedResult) else {
            resultPendingSync = false
            return
        }
        do {
            let response = try await api.submitResult(
                puzzleDate: queued.puzzleDate,
                tz: queued.tz,
                attempts: queued.attempts
            )
            storedResult = response.result
            streak = response.streak
            resultPendingSync = false
            store.remove(key: StoreKey.queuedResult)
            // The reveal is RLS-gated on a stored result, so it can only be fetched now
            // if the original (offline) submit never got one.
            await loadReveal()
            show(toast: "Your score synced.", isError: false)
        } catch let error as KithError {
            if case .api(_, let code, _) = error, code == "already_played" {
                resultPendingSync = false
                store.remove(key: StoreKey.queuedResult)
                await refetchTodayResult()
            }
        } catch {
            // Still offline. Leave it queued.
        }
    }

    private func refetchTodayResult() async {
        guard let results = try? await api.myResults(sinceDate: today) else { return }
        myResults = results
        playedToday = results.contains { $0.puzzle_date == today }
        if let streakValue = try? await api.myStreak() { streak = streakValue }
    }

    // MARK: - Games hub (docs/07, PLAN-games.md)

    /// `"<date>#<game>"`, the key `gameResults` is stored under.
    static func gameKey(date: String, game: GameKind) -> String {
        "\(date)#\(game.rawValue)"
    }

    /// `game_results` rows arrive as `GameResultSummary` (seven columns) but the hub and the
    /// results screen both read `StoredGameResult`. KithCore's wire structs have no public
    /// memberwise init, so the two are bridged the same way `FakeKithAPI` bridges its seeds:
    /// encode a local struct with identical field names and decode the real type.
    static func stored(from summary: GameResultSummary) -> StoredGameResult? {
        struct Seed: Encodable {
            let date: String
            let game: GameKind
            let elapsedMs: Int
            let elapsedSource: String
            let mistakes: Int
            let solved: Bool
            let gaveUp: Bool
            let score: Int
            let submittedAt: String
        }
        return decode(
            Seed(date: summary.date, game: summary.game, elapsedMs: summary.elapsed_ms,
                 elapsedSource: "server", mistakes: summary.mistakes, solved: summary.solved,
                 gaveUp: summary.gave_up, score: summary.score, submittedAt: ""),
            as: StoredGameResult.self
        )
    }

    /// Encode-then-decode bridge for KithCore's initializer-less wire types.
    static func decode<Seed: Encodable, Wire: Decodable>(_ seed: Seed, as: Wire.Type) -> Wire? {
        guard let data = try? JSONEncoder().encode(seed) else { return nil }
        return try? JSONDecoder().decode(Wire.self, from: data)
    }

    /// Today's stored result for a grid game, if it has been played.
    func result(for kind: GameKind) -> StoredGameResult? {
        gameResults[Self.gameKey(date: today, game: kind)]
    }

    /// A grid game is playable only when the server published a row for it today.
    func isAvailable(_ kind: GameKind) -> Bool {
        dailyGames.contains { $0.game == kind && $0.date == today }
    }

    func dailyRow(for kind: GameKind) -> DailyGameRow? {
        dailyGames.first { $0.game == kind && $0.date == today }
    }

    /// The hub row's subtitle (PLAN-games.md "Screens").
    func hubStatus(for game: HubGame) -> String {
        switch game {
        case .lineup:
            guard let row = myResults.first(where: { $0.puzzle_date == today }) else {
                return "Not played"
            }
            let tries = row.tries == 1 ? "1 try" : "\(row.tries) tries"
            return row.solved ? "Solved in \(tries) · \(row.score)" : "Out of tries · \(row.score)"
        case .grid(let kind):
            if let stored = result(for: kind) {
                if stored.gaveUp { return "Gave up" }
                if kind == .quint {
                    let guesses = Self.quintGuessesUsed(stored)
                    return stored.solved
                        ? "Solved in \(guesses) · \(Self.clock(stored.elapsedMs))"
                        : "Failed · \(guesses) guesses"
                }
                if stored.solved { return "Solved · \(Self.clock(stored.elapsedMs))" }
                return "Not solved"
            }
            if kind == .quint {
                return isAvailable(kind) ? "Five letters, six guesses" : "Not available today"
            }
            return isAvailable(kind) ? "Not played" : "Not available today"
        }
    }

    func isHubRowEnabled(_ game: HubGame) -> Bool {
        switch game {
        case .lineup: return true
        case .grid(let kind): return isAvailable(kind) || result(for: kind) != nil
        }
    }

    // MARK: Starting and playing

    /// Fetches the spec and builds the engine for `kind`, keyed into `activeGames` rather
    /// than overwriting a single slot.
    func startGame(_ kind: GameKind) async {
        openGameKind = kind
        // A no-op when that kind is already open and unfinished, so re-entering the
        // screen (or a `.task` firing twice) does not restart the timer. Unlike before,
        // this never clears `activeGames[otherKind]`: opening a different grid game must
        // not destroy another one still in progress (finding A1).
        if let active = activeGames[kind], active.finished == nil { return }
        if result(for: kind) != nil { return }
        activeGameErrors[kind] = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let started = try await api.startGame(date: today, game: kind)
            let engine = try GameEngine(spec: started.spec)
            activeGames[kind] = ActiveGame(started: started, engine: engine, revealedAt: Date())
        } catch {
            activeGameErrors[kind] = message(for: error)
            show(toast: message(for: error), isError: true)
        }
    }

    /// Clears the grid and starts the player over. The clock deliberately keeps running:
    /// the server clamps elapsed against `game_starts` anyway (docs/07). Quint has no
    /// Reset: guesses cannot be undone (docs/08), so the host hides the button and this
    /// guards the model side too.
    func resetGame() {
        guard var active = activeGame, active.finished == nil, active.kind != .quint else { return }
        active.engine.reset()
        active.moves += 1
        activeGame = active
    }

    /// Applies a move and books a mistake when it puts a cell into conflict that was not in
    /// conflict before. `body` returns false when the engine refused the move. `countsMistakes`
    /// lets a caller suppress the count for a move that cannot fairly be judged a mistake yet
    /// (Duo's first tap of a cycle — see `duoCycle`).
    private func applyMove(countsMistakes: Bool = true, _ body: (inout GameEngine) -> Bool) {
        guard var active = activeGame, !active.isFinishing, active.finished == nil else { return }
        let before = active.engine.conflicts
        guard body(&active.engine) else { return }
        let after = active.engine.conflicts
        if countsMistakes, !after.subtracting(before).isEmpty { active.mistakes += 1 }
        active.moves += 1
        activeGame = active
    }

    // The five mutators below all bind the engine with `case let` and mutate a local copy,
    // rather than a `case var` pattern: value semantics either way, and no reliance on a
    // pattern form the compiler has opinions about.

    func starsCycle(at point: GridPoint) {
        applyMove { engine in
            guard case .stars(let current) = engine else { return false }
            var stars = current
            do { try stars.cycle(at: point) } catch { return false }
            engine = .stars(stars)
            return true
        }
    }

    /// Drag-painting: only ever turns an empty cell into a ✕, never disturbs a star.
    func starsPaintCross(at point: GridPoint) {
        applyMove { engine in
            guard case .stars(let current) = engine else { return false }
            guard point.row >= 0, point.row < current.spec.n,
                  point.col >= 0, point.col < current.spec.n,
                  current.marks[point.row][point.col] == .empty else { return false }
            var stars = current
            do { try stars.set(.cross, at: point) } catch { return false }
            engine = .stars(stars)
            return true
        }
    }

    /// The cycle is empty → ● → ○ → empty. The first tap of any cell always lands on ●,
    /// which can transiently be a conflict (a row already at its limit of ●) purely because
    /// the player has not reached the symbol they meant to leave there yet — that is not a
    /// mistake, so only the second and third taps of a cycle (● → ○, ○ → empty) can book one
    /// (finding B2).
    func duoCycle(at point: GridPoint) {
        guard case .duo(let current)? = activeGame?.engine else { return }
        let wasEmpty = current.cells[point.row][point.col] == nil
        applyMove(countsMistakes: !wasEmpty) { engine in
            guard case .duo(let current) = engine else { return false }
            guard !current.isGiven(at: point) else { return false }
            var duo = current
            do { try duo.cycle(at: point) } catch { return false }
            engine = .duo(duo)
            return true
        }
    }

    func trailExtend(to point: GridPoint) {
        applyMove { engine in
            guard case .trail(let current) = engine else { return false }
            var trail = current
            guard trail.extend(to: point) else { return false }
            engine = .trail(trail)
            return true
        }
    }

    func trailRetract(to point: GridPoint) {
        applyMove { engine in
            guard case .trail(let current) = engine else { return false }
            guard current.path.contains(point), current.path.last != point else { return false }
            var trail = current
            trail.retract(to: point)
            engine = .trail(trail)
            return true
        }
    }

    /// Appends a letter to Quint's current row. Not routed through `applyMove`: Quint has
    /// no conflict concept, so there is nothing for that helper's mistake-booking to do.
    func quintType(_ letter: Character) {
        guard var active = activeGame, !active.isFinishing, active.finished == nil,
              case .quint(let current) = active.engine else { return }
        var quint = current
        guard quint.type(letter) else { return }
        active.engine = .quint(quint)
        activeGame = active
    }

    func quintBackspace() {
        guard var active = activeGame, !active.isFinishing, active.finished == nil,
              case .quint(let current) = active.engine else { return }
        var quint = current
        quint.backspace()
        active.engine = .quint(quint)
        activeGame = active
    }

    /// Submits Quint's current row. `mistakes` is kept as `wrongGuesses` after every
    /// accepted guess (docs/07: "Mistakes on the results screen = wrong guesses"), a
    /// `.notAWord` outcome bumps `quintShake` so `QuintView` can animate it, and an
    /// `.accepted` guess that completes the puzzle (solved or six wrong guesses) hands off
    /// to `finishGame()` — the same completion path Done uses for the other three games.
    @discardableResult
    func quintSubmit() -> QuintEngine.SubmitOutcome {
        guard var active = activeGame, !active.isFinishing, active.finished == nil,
              case .quint(let current) = active.engine else { return .tooShort }
        var quint = current
        let outcome = quint.submit()
        switch outcome {
        case .accepted:
            active.engine = .quint(quint)
            active.mistakes = quint.wrongGuesses
            active.moves += 1
            activeGame = active
            if quint.isComplete {
                Task { await self.finishGame() }
            }
        case .notAWord:
            active.quintShake += 1
            activeGame = active
        case .tooShort, .finished:
            break
        }
        return outcome
    }

    // MARK: Finishing

    /// Submits the completed grid. Does nothing while the engine says it is not complete.
    func finishGame() async {
        guard let active = activeGame, !active.isFinishing, active.finished == nil,
              let answer = active.engine.answer else { return }
        await submit(active, gaveUp: false, answer: answer)
    }

    /// "Give up" reveals the solution server-side and scores 100 (docs/07).
    func giveUpGame() async {
        guard let active = activeGame, !active.isFinishing, active.finished == nil else { return }
        await submit(active, gaveUp: true, answer: nil)
    }

    private func submit(_ active: ActiveGame, gaveUp: Bool, answer: GameAnswer?) async {
        var game = active
        game.isFinishing = true
        let kind = game.kind
        activeGames[kind] = game

        let elapsed = game.elapsedMs
        isBusy = true
        defer { isBusy = false }

        // Quint can finish "not solved" without giving up (a sixth wrong guess), unlike the
        // other three games where any non-give-up finish is by definition solved — so the
        // local/offline fallback result needs the engine's own verdict rather than `!gaveUp`.
        let solved: Bool
        if case .quint(let engine) = game.engine {
            solved = engine.isSolved
        } else {
            solved = !gaveUp
        }

        game.finished = await submitGame(kind: kind, elapsedMs: elapsed, mistakes: game.mistakes,
                                         gaveUp: gaveUp, answer: answer, retryNoStart: true,
                                         solved: solved)

        game.isFinishing = false
        activeGames[kind] = game
        showGameResults = true

        await refreshBoard(kind: .friends, scopeId: nil, period: .today,
                           game: HubGame.grid(kind).boardGame, force: true)
        _ = try? await api.track("game_submit", props: ["date": today, "game": kind.rawValue])
    }

    /// Submits one grid game and settles on the `StoredGameResult` the UI shows, whatever
    /// the server said:
    /// - success → the server's own result;
    /// - `already_played` (409) → treated as success, refetched from `game_results`;
    /// - `no_start` (409, the caller never called `start_game` for this date/game) → replay
    ///   `start_game` once and retry the submit exactly once more (`retryNoStart` guards
    ///   against looping if the retry also comes back `no_start`);
    /// - anything else → queued for `retryQueuedGames`.
    private func submitGame(kind: GameKind, elapsedMs: Int, mistakes: Int, gaveUp: Bool,
                            answer: GameAnswer?, retryNoStart: Bool,
                            solved: Bool) async -> StoredGameResult? {
        do {
            let response = try await api.submitGame(
                date: today, game: kind, tz: tz, elapsedMs: elapsedMs,
                mistakes: mistakes, gaveUp: gaveUp, answer: answer
            )
            gameResults[Self.gameKey(date: today, game: kind)] = response.result
            streak = response.streak
            return response.result
        } catch let error as KithError {
            if case .api(_, let code, _) = error, code == "already_played" {
                await refreshGameResults()
                return result(for: kind) ?? Self.localGameResult(
                    date: today, game: kind, elapsedMs: elapsedMs, mistakes: mistakes,
                    gaveUp: gaveUp, solved: solved
                )
            }
            if case .api(_, let code, _) = error, code == "no_start", retryNoStart {
                _ = try? await api.startGame(date: today, game: kind)
                return await submitGame(kind: kind, elapsedMs: elapsedMs, mistakes: mistakes,
                                        gaveUp: gaveUp, answer: answer, retryNoStart: false,
                                        solved: solved)
            }
            return queueGame(kind: kind, elapsedMs: elapsedMs, mistakes: mistakes,
                             gaveUp: gaveUp, answer: answer, solved: solved)
        } catch {
            return queueGame(kind: kind, elapsedMs: elapsedMs, mistakes: mistakes,
                             gaveUp: gaveUp, answer: answer, solved: solved)
        }
    }

    /// The result the UI shows while a submission is still queued. Score is computed with
    /// the same rule the server uses (`GameScoring`), so the number does not jump on sync.
    /// `solved` comes from the caller rather than being derived from `gaveUp` here: for the
    /// three grid games any non-give-up finish is solved by construction, but Quint can also
    /// finish "not solved" (a sixth wrong guess) without giving up.
    private static func localGameResult(date: String, game: GameKind, elapsedMs: Int,
                                        mistakes: Int, gaveUp: Bool, solved: Bool) -> StoredGameResult? {
        struct Seed: Encodable {
            let date: String
            let game: GameKind
            let elapsedMs: Int
            let elapsedSource: String
            let mistakes: Int
            let solved: Bool
            let gaveUp: Bool
            let score: Int
            let submittedAt: String
        }
        let score: Int
        if game == .quint {
            // `mistakes` is Quint's wrong-guess count; the total guesses made is one more
            // than that when the puzzle was solved (the winning guess is not "wrong").
            let guesses = mistakes + (solved ? 1 : 0)
            score = GameScoring.quintScore(elapsedMs: elapsedMs, guesses: guesses,
                                           solved: solved, gaveUp: gaveUp)
        } else {
            score = GameScoring.score(elapsedMs: elapsedMs, gaveUp: gaveUp)
        }
        return decode(
            Seed(date: date, game: game, elapsedMs: elapsedMs, elapsedSource: "client",
                 mistakes: mistakes, solved: solved, gaveUp: gaveUp,
                 score: score, submittedAt: ""),
            as: StoredGameResult.self
        )
    }

    @discardableResult
    private func queueGame(kind: GameKind, elapsedMs: Int, mistakes: Int,
                           gaveUp: Bool, answer: GameAnswer?, solved: Bool) -> StoredGameResult? {
        var queue = store.load([QueuedGameResult].self, key: StoreKey.queuedGameResults) ?? []
        queue.removeAll { $0.date == today && $0.game == kind }
        queue.append(QueuedGameResult(date: today, game: kind, tz: tz, elapsedMs: elapsedMs,
                                      mistakes: mistakes, gaveUp: gaveUp, answer: answer))
        store.save(queue, key: StoreKey.queuedGameResults)
        gamePendingSync = true
        show(toast: "Offline. Your score will sync.", isError: false)
        let local = Self.localGameResult(date: today, game: kind, elapsedMs: elapsedMs,
                                         mistakes: mistakes, gaveUp: gaveUp, solved: solved)
        if let local { gameResults[Self.gameKey(date: today, game: kind)] = local }
        return local
    }

    /// Everything still waiting to be replayed. The seam `KithTests` uses instead of
    /// guessing the file path, exactly like `queuedResult`.
    var queuedGameResults: [QueuedGameResult] {
        store.load([QueuedGameResult].self, key: StoreKey.queuedGameResults) ?? []
    }

    func retryQueuedGames() async {
        let queue = store.load([QueuedGameResult].self, key: StoreKey.queuedGameResults) ?? []
        guard !queue.isEmpty else {
            gamePendingSync = false
            return
        }
        var remaining: [QueuedGameResult] = []
        for item in queue {
            do {
                let response = try await api.submitGame(
                    date: item.date, game: item.game, tz: item.tz, elapsedMs: item.elapsedMs,
                    mistakes: item.mistakes, gaveUp: item.gaveUp, answer: item.answer
                )
                gameResults[Self.gameKey(date: item.date, game: item.game)] = response.result
                streak = response.streak
            } catch let error as KithError {
                // `already_played` means the server has it: dropping it from the queue is
                // the success path, exactly as for Lineup.
                if case .api(_, let code, _) = error, code == "already_played" { continue }
                remaining.append(item)
            } catch {
                remaining.append(item)
            }
        }
        if remaining.isEmpty {
            store.remove(key: StoreKey.queuedGameResults)
            gamePendingSync = false
            show(toast: "Your score synced.", isError: false)
        } else {
            store.save(remaining, key: StoreKey.queuedGameResults)
            gamePendingSync = true
        }
    }

    // MARK: Games presentation

    /// "Solved!" / "Gave up" / "Failed" (Quint) / "Not solved" (the other three games) for
    /// `GameResultsView` (finding C6).
    static func gameHeadline(_ result: StoredGameResult) -> String {
        if result.gaveUp { return "Gave up" }
        if result.solved { return "Solved!" }
        return result.game == .quint ? "Failed" : "Not solved"
    }

    /// The share text for a finished grid game (`GameShareText.render`).
    func gameShareText(_ result: StoredGameResult, rows: [String]) -> String {
        let number = activeGames[result.game]?.number ?? dailyRow(for: result.game)?.number ?? 0
        return GameShareText.render(
            game: result.game,
            number: number,
            elapsedMs: result.elapsedMs,
            gaveUp: result.gaveUp,
            rows: rows,
            refCode: profile?.invite_code,
            quintProgress: result.game == .quint ? Self.quintProgress(result) : nil
        )
    }

    /// Guesses actually made: `mistakes` (wrong guesses) plus one more when the puzzle was
    /// solved, since the winning guess is not itself "wrong".
    static func quintGuessesUsed(_ result: StoredGameResult) -> Int {
        result.mistakes + (result.solved ? 1 : 0)
    }

    /// "4/6" once solved, "X/6" after six wrong guesses, or "<n>/6" for a give-up part way
    /// through (docs/07 §Quint share text) — used by both the share text and the results
    /// subtitle so the two numbers always agree.
    static func quintProgress(_ result: StoredGameResult, maxGuesses: Int = 6) -> String {
        let used = quintGuessesUsed(result)
        if !result.solved, used >= maxGuesses { return "X/\(maxGuesses)" }
        return "\(used)/\(maxGuesses)"
    }

    /// `markShared`'s counterpart for a grid game: `GameResultsView` calls this instead,
    /// since Lineup's `shareCompleted` flag (and its "Shared" label) is not this game's to
    /// borrow — sharing Stars should not silently mark Lineup shared too (finding C5).
    func markGameShared(_ kind: GameKind) {
        Task { _ = try? await self.api.track("share_complete", props: ["date": self.today, "game": kind.rawValue]) }
    }

    /// "2nd of 5 friends on Stars today", or nil when nobody else has played.
    func gameRankTeaser(for kind: GameKind) -> String? {
        let board = HubGame.grid(kind).boardGame
        let all = rows(kind: .friends, scopeId: nil, period: .today, game: board)
        guard let me = all.first(where: \.isMe), let rank = me.rank else { return nil }
        let played = all.filter(\.played).count
        guard played > 1 else { return nil }
        return "\(Self.ordinal(rank)) of \(played) friends on \(kind.title) today"
    }

    static func ordinal(_ value: Int) -> String {
        switch value % 100 {
        case 11, 12, 13: return "\(value)th"
        default: break
        }
        switch value % 10 {
        case 1: return "\(value)st"
        case 2: return "\(value)nd"
        case 3: return "\(value)rd"
        default: return "\(value)th"
        }
    }

    /// Days played and best solved time per grid game, for the profile breakdown.
    var gameStats: [GameStat] {
        GameKind.allCases.map { kind in
            let mine = myGameResults.filter { $0.game == kind }
            let best = mine.filter { $0.solved && !$0.gave_up }.map(\.elapsed_ms).min()
            return GameStat(game: kind, daysPlayed: mine.count, bestMs: best)
        }
    }

    // MARK: - Results screen data

    var resultsSummary: ResultsSummary? {
        guard let localResult, let puzzle else { return nil }
        let friendRows = boards[BoardCacheKey(kind: .friends, scopeId: nil, period: .today, date: today)] ?? []
        return ResultsPresenter.summary(
            result: localResult,
            puzzleNumber: puzzle.number,
            streak: streak,
            refCode: profile?.invite_code,
            friendRows: friendRows,
            me: myUserId
        )
    }

    /// The five items in the correct order, labels only. Used by the reveal strip as a
    /// fallback when `reveal` (values and facts) could not be loaded — e.g. offline.
    var revealItems: [PuzzleItem] {
        guard let puzzle else { return [] }
        return puzzle.correctOrder.compactMap { id in puzzle.items.first { $0.id == id } }
    }

    func markShared() {
        shareCompleted = true
        Task { _ = try? await self.api.track("share_complete", props: ["date": self.today]) }
    }

    /// Write-once per day: `taunts` rejects a second insert with a 409, so once one has
    /// landed the field is closed for the rest of the day.
    func saveTaunt() async {
        guard !tauntSaved else { return }
        let text = tauntDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 80 else { return }
        do {
            try await api.setTaunt(date: today, text: text)
            tauntSaved = true
            show(toast: "Saved.", isError: false)
        } catch {
            show(toast: "Couldn't save that.", isError: true)
        }
    }

    // MARK: - Board

    func rows(kind: BoardKind, scopeId: String?, period: BoardPeriod,
              game: BoardGame = .lineup) -> [BoardDisplayRow] {
        let key = BoardCacheKey(kind: kind, scopeId: scopeId, period: period, date: today, game: game)
        let raw = boards[key] ?? []
        // Contact names are only used where the viewer actually knows the person.
        let overrides: [String: String] = kind == .everyone ? [:] : friendNames
        return BoardPresenter.rows(
            raw,
            me: myUserId,
            period: period,
            nameOverride: overrides,
            taunts: playedToday ? taunts : [],
            reactions: reactions
        )
    }

    func boardHeader(kind: BoardKind, scopeId: String?, period: BoardPeriod,
                     game: BoardGame = .lineup) -> String {
        let key = BoardCacheKey(kind: kind, scopeId: scopeId, period: period, date: today, game: game)
        let raw = boards[key] ?? []
        let others = raw.filter { $0.user_id != myUserId }
        return BoardPresenter.headerText(played: others.filter(\.played).count, total: others.count)
    }

    /// Elapsed milliseconds per user for a cached board. `BoardDisplayRow` (KithCore, frozen)
    /// carries no time, and the grid-game boards show time instead of a mini grid, so the
    /// raw rows are consulted for that one column.
    func elapsedMsByUser(kind: BoardKind, scopeId: String?, period: BoardPeriod,
                         game: BoardGame) -> [String: Int] {
        let key = BoardCacheKey(kind: kind, scopeId: scopeId, period: period, date: today, game: game)
        var map: [String: Int] = [:]
        for row in boards[key] ?? [] {
            if let elapsed = row.elapsed_ms { map[row.user_id] = elapsed }
        }
        return map
    }

    func refreshBoard(kind: BoardKind, scopeId: String?, period: BoardPeriod,
                      game: BoardGame = .lineup, force: Bool = false) async {
        let key = BoardCacheKey(kind: kind, scopeId: scopeId, period: period, date: today, game: game)
        // A board that failed last time is never served from the cache: retry it.
        if !force, boards[key] != nil, !failedBoards.contains(key) { return }
        do {
            let rows = try await api.board(kind: kind, scopeId: scopeId, period: period,
                                           date: today, game: game)
            boards[key] = rows
            failedBoards.remove(key)
        } catch {
            failedBoards.insert(key)
            // Only a forced load may write an empty board, so a network blip on the way
            // in doesn't render as a permanent "nobody has played".
            if force, boards[key] == nil { boards[key] = [] }
        }
        if period == .today {
            taunts = (try? await api.taunts(date: today)) ?? taunts
            reactions = (try? await api.reactions(date: today)) ?? reactions
        }
    }

    func react(to userId: String, emoji: String) async {
        let existing = reactions.first { $0.from_user == myUserId && $0.to_user == userId }
        do {
            if existing?.emoji == emoji {
                try await api.unreact(to: userId, date: today)
            } else {
                // One reaction per person per day. Swapping emoji has to clear the old
                // row first: the upsert merges on the primary key, but the server counts
                // a change as a new reaction and would otherwise re-notify.
                if existing != nil {
                    try await api.unreact(to: userId, date: today)
                }
                try await api.react(to: userId, date: today, emoji: emoji)
            }
            reactions = (try? await api.reactions(date: today)) ?? reactions
        } catch {
            show(toast: "Couldn't send that.", isError: true)
        }
    }

    func hideTaunt(author: String) async {
        try? await api.hideTaunt(author: author, date: today)
        taunts = (try? await api.taunts(date: today)) ?? taunts
    }

    // MARK: - Circles

    func loadCircles() async {
        guard let loaded = try? await api.myCircles() else { return }
        circles = loaded
        if selectedCircleId == nil { selectedCircleId = loaded.first?.id }
    }

    func createCircle(name: String) async {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !trimmed.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let circle = try await api.createCircle(name: trimmed)
            circles.append(circle)
            selectedCircleId = circle.id
            showCreateCircleSheet = false
            show(toast: "Circle created.", isError: false)
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    func joinCircle(code: String) async {
        let cleaned = Self.normalizedJoinCode(code)
        guard !cleaned.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let id = try await api.joinCircle(code: cleaned)
            await loadCircles()
            selectedCircleId = id
            showJoinSheet = false
            pendingJoinCode = nil
            tab = .circles
            show(toast: "You're in.", isError: false)
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    func leaveCircle(id: String) async {
        do {
            try await api.leaveCircle(id: id)
            circles.removeAll { $0.id == id }
            if selectedCircleId == id { selectedCircleId = circles.first?.id }
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    /// "kith-7f3q", "KITH-7F3Q" and "7F3Q" all mean the same code.
    static func normalizedJoinCode(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("KITH-") { value = String(value.dropFirst(5)) }
        return value.filter { $0.isLetter || $0.isNumber }
    }

    func circleLink(_ circle: Circle) -> String {
        "\(AppConfig.webBase.absoluteString)/c/\(circle.code)"
    }

    // MARK: - Contacts

    func requestContactsAccess() async {
        contactsState = await ContactsService.requestAccess()
        onboarding.apply(.contactsDecided)
        showContactsReask = false
        if contactsState.allowsFetch {
            show(toast: "Finding your friends…", isError: false)
            await syncContacts(userInitiated: true)
        }
    }

    func declineContacts() {
        contactsState = ContactsService.authorizationState()
        onboarding.apply(.contactsDecided)
        showContactsReask = false
    }

    func syncContacts(userInitiated: Bool) async {
        guard contactsState.allowsFetch, !isSyncingContacts else { return }
        isSyncingContacts = true
        defer { isSyncingContacts = false }
        do {
            let outcome = try await ContactsService.sync(api: api, lastSynced: lastSyncedHashes)
            directory = outcome.directory
            sharedContactCount = outcome.sharedCount
            store.save(directory, key: StoreKey.directory)

            if !outcome.friends.isEmpty || !outcome.matches.isEmpty {
                friends = outcome.friends
                var names = friendNames
                for friend in outcome.friends {
                    names[friend.userId] = FriendNames.displayName(
                        for: friend,
                        matches: outcome.matches,
                        directory: outcome.directory
                    )
                }
                friendNames = names
                store.save(names, key: StoreKey.friendNames)
            }

            lastSyncedHashes = outcome.syncedHashes
            store.save(Array(outcome.syncedHashes).sorted(), key: StoreKey.syncedHashes)
            let now = Date()
            lastContactSync = now
            store.save(Timestamp(now), key: StoreKey.lastContactSync)

            if userInitiated {
                let count = friends.count
                show(toast: count == 1 ? "1 friend found" : "\(count) friends found", isError: false)
            }
            await refreshBoard(kind: .friends, scopeId: nil, period: .today, force: true)
        } catch {
            if userInitiated {
                show(toast: message(for: error), isError: true)
            }
        }
    }

    var contactsStatusLine: String {
        contactsState.statusLine(sharedCount: sharedContactCount, lastSync: lastContactSync)
    }

    /// Rows for the "N of your contacts already play" onboarding tail.
    var friendPreview: [BoardDisplayRow] {
        Array(rows(kind: .friends, scopeId: nil, period: .today).filter { !$0.isMe }.prefix(3))
    }

    // MARK: - Onboarding

    /// The number as Supabase Auth needs it: E.164, no spaces, dashes, dots or parentheses,
    /// with the device region's calling code added when the person typed no "+". The same
    /// normaliser the contact matcher uses (KithCore `BasicPhoneNormalizer`), so
    /// "(571) 341-0690" on a US phone becomes "+15713410690" and matches its own hash.
    /// `nil` when the input cannot be a phone number at all.
    static func normalizedPhone(_ raw: String, region: String = ContactsService.region) -> String? {
        BasicPhoneNormalizer().e164(raw, defaultRegion: region)
    }

    /// The E.164 form of `phoneDraft` once `sendCode` has accepted it; `verifyCode` and
    /// `resendCode` must send exactly the string the code was sent to.
    var phoneE164: String?

    func sendCode() async {
        guard let phone = Self.normalizedPhone(phoneDraft) else {
            show(toast: "That doesn't look like a phone number. Include your area code, e.g. (555) 123-4567.",
                 isError: true)
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.sendCode(phone: phone)
            phoneE164 = phone
            onboarding.apply(.phoneEntered(phone))
            resendAvailableAt = Date().addingTimeInterval(30)
            codeDraft = ""
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    func resendCode() async {
        guard let resendAvailableAt, Date() >= resendAvailableAt else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.sendCode(phone: phoneE164 ?? phoneDraft)
            self.resendAvailableAt = Date().addingTimeInterval(30)
            show(toast: "Code sent.", isError: false)
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    func verifyCode() async {
        let code = codeDraft.filter(\.isNumber)
        guard code.count == 6 else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            myUserId = try await auth.verify(phone: phoneE164 ?? phoneDraft, code: code) ?? ""
            onboarding.apply(.codeVerified)
            stage = .registering
            // Returning user: the row already exists, skip straight to the puzzle.
            if let existing = try? await api.profile() {
                profile = existing
                myUserId = existing.id
                nameDraft = existing.display_name
                stage = .ready
                onboarding.apply(.nameSaved)
                onboarding.apply(.contactsDecided)
                await loadToday()
                await refreshBoard(kind: .friends, scopeId: nil, period: .today)
            }
        } catch {
            codeDraft = ""
            show(toast: "That code didn't work.", isError: true)
        }
    }

    func backFromCode() {
        onboarding.apply(.back)
        codeDraft = ""
    }

    func saveName() async {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await api.register(displayName: name, tz: tz)
            myUserId = response.userId
            profile = try? await api.profile()
            stage = .ready
            onboarding.apply(.nameSaved)
            // The contacts pre-prompt is next, and it sits on top of Today; the puzzle
            // has to be in hand by the time it is dismissed (docs/02 §6 step 1e).
            await loadToday()
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    /// Called once the first results screen has been seen (docs/02 §6 step 7).
    func firstResultShown() async {
        onboarding.apply(.firstResultShown)
        tail = .friendsFound
        await refreshBoard(kind: .friends, scopeId: nil, period: .today, force: true)
    }

    func advanceTail() {
        switch tail {
        case .friendsFound: tail = .notifications
        case .notifications, .none: tail = .none
        }
    }

    func enableNotifications() async {
        let granted = await PushService.shared.requestAuthorization()
        if granted {
            _ = try? await api.updateProfile(
                ProfilePatch(push_daily: true, push_daily_at: notificationTime + ":00")
            )
        }
        tail = .none
        // `requestAuthorization` only registers for APNs on a fresh grant; this also
        // covers the case where permission was already there from a previous install.
        await PushService.shared.registerIfAuthorized()
    }

    private func wirePush() {
        PushService.shared.onToken = { [weak self] token in
            guard let self else { return }
            Task { _ = try? await self.api.registerDevice(apnsToken: token, env: AppConfig.pushEnvironment) }
        }
        PushService.shared.onRegistrationError = { _ in
            // Free-team sideloads have no aps-environment entitlement. Ignore.
        }
        PushService.shared.onDeepLink = { [weak self] url in
            self?.route(url)
        }
        Task { await PushService.shared.registerIfAuthorized() }
    }

    // MARK: - Profile

    var heatmap: [HeatCell] {
        ProfilePresenter.heatmap(results: heatmapResults, today: today)
    }

    /// docs/07: a day counts when *any* game was played, so days with only a grid-game
    /// result are folded in as synthetic Lineup rows. `tries: 2` keeps such a day "played"
    /// rather than "solved on the first try" — a grid game has one attempt and no tries.
    private var heatmapResults: [ResultSummary] {
        struct Seed: Encodable {
            let puzzle_date: String
            let tries: Int
            let solved: Bool
            let score: Int
        }
        var byDate = Dictionary(myResults.map { ($0.puzzle_date, $0) },
                                uniquingKeysWith: { first, _ in first })
        for summary in myGameResults where byDate[summary.date] == nil {
            // A gave-up day still counts as played for the heatmap (docs/07): only a day
            // with no result at all is "unsolved" (finding B6).
            guard let row = Self.decode(
                Seed(puzzle_date: summary.date, tries: 2,
                     solved: summary.solved || summary.gave_up, score: summary.score),
                as: ResultSummary.self
            ) else { continue }
            byDate[summary.date] = row
        }
        return byDate.values.sorted { $0.puzzle_date < $1.puzzle_date }
    }

    var stats: ProfileStats {
        ProfilePresenter.stats(results: myResults)
    }

    func loadProfileData() async {
        if let results = try? await api.myResults(sinceDate: "2020-01-01") {
            myResults = results
        }
        if let games = try? await api.myGameResults(sinceDate: "2020-01-01") {
            myGameResults = games
        }
        if let streakValue = try? await api.myStreak() { streak = streakValue }
        if let loaded = try? await api.profile() { profile = loaded }
    }

    func updateProfile(_ patch: ProfilePatch) async {
        do {
            try await api.updateProfile(patch)
            profile = try? await api.profile()
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    func signOut() async {
        await auth.signOut()
        store.removeAll()
        resetLocalState()
        stage = .signedOut
    }

    func deleteAccount() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.deleteAccount()
            await auth.signOut()
            store.removeAll()
            resetLocalState()
            stage = .signedOut
        } catch {
            show(toast: message(for: error), isError: true)
        }
    }

    private func resetLocalState() {
        profile = nil
        myUserId = ""
        puzzle = nil
        engine = nil
        revealedAt = nil
        localResult = nil
        storedResult = nil
        playedToday = false
        streak = 0
        reveal = []
        tauntDraft = ""
        tauntSaved = false
        boards = [:]
        failedBoards = []
        taunts = []
        reactions = []
        circles = []
        selectedCircleId = nil
        myResults = []
        dailyGames = []
        gameResults = [:]
        myGameResults = []
        activeGames = [:]
        openGameKind = nil
        activeGameErrors = [:]
        showGameResults = false
        gamePendingSync = false
        directory = ContactDirectory()
        friends = []
        friendNames = [:]
        lastSyncedHashes = nil
        lastContactSync = nil
        showContactsReask = false
        onboarding = OnboardingFlow()
        tail = .none
        phoneDraft = ""
        phoneE164 = nil
        codeDraft = ""
        nameDraft = ""
        tab = .today
        showResults = false
        midnight.stop()
    }

    // MARK: - Routing

    /// `kith://today`, `kith://board`, `https://kith.app/c/<code>`, `https://kith.app/p/<n>`.
    func route(_ url: URL) {
        if url.scheme == "kith" {
            let target = url.host() ?? url.path.replacingOccurrences(of: "/", with: "")
            switch target {
            case "today": tab = .today
            case "board": tab = .board
            case "circles": tab = .circles
            case "you", "profile": tab = .you
            case "c":
                let code = url.pathComponents.filter { $0 != "/" }.last ?? ""
                openJoin(code: code)
            default: tab = .today
            }
            return
        }

        guard url.host() == AppConfig.webHost else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { tab = .today; return }
        switch first {
        case "c":
            openJoin(code: parts.count > 1 ? parts[1] : "")
        case "p":
            tab = .today
        default:
            tab = .today
        }
    }

    private func openJoin(code: String) {
        let cleaned = Self.normalizedJoinCode(code)
        guard !cleaned.isEmpty else { return }
        pendingJoinCode = cleaned
        tab = .circles
        showJoinSheet = true
    }

    // MARK: - Presentation helpers (model layer, so views stay dumb)

    /// "Thursday, Sep 11" for the Today header.
    static func headerDate(_ dateString: String) -> String {
        let weekday = LocalDay.weekdayName(dateString)
        let parts = dateString.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month) else {
            return weekday
        }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(weekday), \(months[month - 1]) \(day)"
    }

    /// "0:32" from milliseconds.
    static func clock(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds) / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// A reveal-strip value: whole numbers keep no decimals ("1817"), anything else gets
    /// up to two ("2.5", "3.14"). Years, counts and prices all read correctly this way.
    static func revealValue(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    var countdownText: String {
        LocalDay.countdownText(seconds: LocalDay.secondsUntilMidnight(Date(), tz: tz))
    }

    func show(toast text: String, isError: Bool) {
        let message = ToastMessage(text: text, isError: isError)
        toast = message
        if isError { lastErrorMessage = text }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, self.toast?.id == message.id else { return }
            self.toast = nil
        }
    }

    func message(for error: Error) -> String {
        guard let error = error as? KithError else { return "Something went wrong." }
        switch error {
        case .notSignedIn: return "You're signed out."
        case .network: return "No connection."
        case .api(_, _, let message): return message
        case .decoding: return "The server sent something unexpected."
        }
    }
}
