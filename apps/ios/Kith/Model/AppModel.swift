// AppModel.swift — the single observable object the whole app reads.
//
// Rules (apps/ios/PLAN.md): no logic here that belongs in KithCore, every network
// call goes through `KithAPI`, the engine is a value type mutated through methods so
// SwiftUI sees the change.

import Foundation
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
        maybeReaskForContacts()
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

    func rows(kind: BoardKind, scopeId: String?, period: BoardPeriod) -> [BoardDisplayRow] {
        let key = BoardCacheKey(kind: kind, scopeId: scopeId, period: period, date: today)
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

    func boardHeader(kind: BoardKind, scopeId: String?, period: BoardPeriod) -> String {
        let key = BoardCacheKey(kind: kind, scopeId: scopeId, period: period, date: today)
        let raw = boards[key] ?? []
        let others = raw.filter { $0.user_id != myUserId }
        return BoardPresenter.headerText(played: others.filter(\.played).count, total: others.count)
    }

    func refreshBoard(kind: BoardKind, scopeId: String?, period: BoardPeriod, force: Bool = false) async {
        let key = BoardCacheKey(kind: kind, scopeId: scopeId, period: period, date: today)
        // A board that failed last time is never served from the cache: retry it.
        if !force, boards[key] != nil, !failedBoards.contains(key) { return }
        do {
            let rows = try await api.board(kind: kind, scopeId: scopeId, period: period, date: today)
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

    func sendCode() async {
        let phone = phoneDraft.trimmingCharacters(in: .whitespaces)
        guard phone.count >= 8 else {
            show(toast: "That number looks too short.", isError: true)
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.sendCode(phone: phone)
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
            try await auth.sendCode(phone: phoneDraft)
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
            myUserId = try await auth.verify(phone: phoneDraft, code: code) ?? ""
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
        ProfilePresenter.heatmap(results: myResults, today: today)
    }

    var stats: ProfileStats {
        ProfilePresenter.stats(results: myResults)
    }

    func loadProfileData() async {
        if let results = try? await api.myResults(sinceDate: "2020-01-01") {
            myResults = results
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
        directory = ContactDirectory()
        friends = []
        friendNames = [:]
        lastSyncedHashes = nil
        lastContactSync = nil
        showContactsReask = false
        onboarding = OnboardingFlow()
        tail = .none
        phoneDraft = ""
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
