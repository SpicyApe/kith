// Persistence.swift — a tiny JSON file store in Application Support.
//
// Nothing here is secret (the auth session lives in the Keychain, owned by
// supabase-swift). These files are a cache: the contact directory, the last synced
// hash set, today's puzzle, the last local result, and one queued offline result.

import Foundation
import GridGames
import KithCore
import LineupEngine

/// A result that could not be submitted because the network was down.
struct QueuedResult: Codable, Sendable, Equatable {
    let puzzleDate: String
    let tz: String
    let attempts: [Attempt]
}

/// The same idea for a grid game. `GameAnswer` is `Encodable` only (KithCore contract),
/// so the three possible answer shapes are stored as plain arrays and rebuilt on replay.
/// Unlike Lineup there can be three of these pending at once, so the store holds an array.
struct QueuedGameResult: Codable, Sendable, Equatable {
    let date: String
    let game: GameKind
    let tz: String
    let elapsedMs: Int
    let mistakes: Int
    let gaveUp: Bool
    var stars: [Int]?
    var cells: [[Int]]?
    var path: [[Int]]?
    var guesses: [String]?

    init(date: String, game: GameKind, tz: String, elapsedMs: Int, mistakes: Int,
         gaveUp: Bool, answer: GameAnswer?) {
        self.date = date
        self.game = game
        self.tz = tz
        self.elapsedMs = elapsedMs
        self.mistakes = mistakes
        self.gaveUp = gaveUp
        switch answer {
        case .stars(let value): self.stars = value
        case .duo(let value): self.cells = value
        case .trail(let value): self.path = value
        case .quint(let value): self.guesses = value
        case nil: break
        }
    }

    /// Rebuilds the `answer` the queued submission has to send. Nil for a give-up.
    var answer: GameAnswer? {
        if let stars { return .stars(stars) }
        if let cells { return .duo(cells) }
        if let path { return .trail(path) }
        if let guesses { return .quint(guesses) }
        return nil
    }
}

/// Top-level JSON fragments are awkward to round-trip, so dates get a box.
struct Timestamp: Codable, Sendable, Equatable {
    let value: Date
    init(_ value: Date) { self.value = value }
}

/// Everything the app persists, keyed by file name.
enum StoreKey {
    static let directory = "contact-directory"
    static let syncedHashes = "synced-hashes"
    static let lastContactSync = "last-contact-sync"
    static let cachedPuzzle = "cached-puzzle"
    static let localResult = "local-result"
    static let queuedResult = "queued-result"
    /// `[QueuedGameResult]` — the grid-game equivalent of `queuedResult` (docs/07).
    static let queuedGameResults = "queued-game-results"
    static let friendNames = "friend-names"
    /// Set once the contacts pre-prompt has been shown a second time (`AppModel.maybeReaskForContacts`).
    static let contactsReasked = "contacts-reasked"
}

struct FileStore: Sendable {
    static let shared = FileStore()

    private let directory: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folder = base.appendingPathComponent("Kith", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.directory = folder
    }

    /// A store rooted anywhere. `KithTests` and the `-uiTesting` launch point this at a
    /// fresh directory under `FileManager.default.temporaryDirectory` so each run starts
    /// with an empty cache and never touches the real one (TESTING.md §1).
    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
    }

    /// Where this store keeps its files. Tests assert on the queued-result file.
    var root: URL { directory }

    private func url(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("json")
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// Wipes every cached file. Used after "delete account" and after sign-out.
    func removeAll() {
        let keys = [
            StoreKey.directory, StoreKey.syncedHashes, StoreKey.lastContactSync,
            StoreKey.cachedPuzzle, StoreKey.localResult, StoreKey.queuedResult,
            StoreKey.queuedGameResults, StoreKey.friendNames, StoreKey.contactsReasked
        ]
        for key in keys { remove(key: key) }
    }
}
