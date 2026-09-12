// Persistence.swift — a tiny JSON file store in Application Support.
//
// Nothing here is secret (the auth session lives in the Keychain, owned by
// supabase-swift). These files are a cache: the contact directory, the last synced
// hash set, today's puzzle, the last local result, and one queued offline result.

import Foundation
import KithCore
import LineupEngine

/// A result that could not be submitted because the network was down.
struct QueuedResult: Codable, Sendable, Equatable {
    let puzzleDate: String
    let tz: String
    let attempts: [Attempt]
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
            StoreKey.friendNames, StoreKey.contactsReasked
        ]
        for key in keys { remove(key: key) }
    }
}
