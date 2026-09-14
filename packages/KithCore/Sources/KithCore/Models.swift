// Models.swift — wire types mirroring the Supabase schema and edge-function
// responses. Field names match the server JSON exactly (snake_case where PostgREST
// returns table columns, camelCase where an edge function builds the body).
//
// CONTRACT FILE: data only; no bodies to implement here.

import Foundation
import LineupEngine

// MARK: Edge function responses

public struct RegisterResponse: Codable, Sendable, Equatable {
    public let userId: String
    public let displayName: String
    public let inviteCode: String
    public let existing: Bool
}

public struct StoredResult: Codable, Sendable, Equatable {
    public let puzzleDate: String
    public let tries: Int
    public let solved: Bool
    public let elapsedMs: Int
    public let score: Int
    public let attempts: [Attempt]
    public let elapsedSource: String
    public let submittedAt: String
}

public struct SubmitResponse: Codable, Sendable, Equatable {
    public let result: StoredResult
    public let streak: Int
}

public struct MatchedContact: Codable, Sendable, Equatable, Hashable {
    public let userId: String
    public let displayName: String
    public let hash: String
}

public struct Friend: Codable, Sendable, Equatable, Hashable {
    public let userId: String
    public let displayName: String
}

public struct MatchResponse: Codable, Sendable, Equatable {
    public let matches: [MatchedContact]
    public let friends: [Friend]
    public let stored: Int
}

/// Error body every edge function returns on 4xx.
public struct APIErrorBody: Codable, Sendable, Equatable {
    public let error: String
    public let code: String
}

// MARK: PostgREST rows

/// One row of `board(kind, scope_id, period, for_date)`.
public struct BoardRow: Codable, Sendable, Equatable {
    public let user_id: String
    public let display_name: String
    public let score: Int
    public let tries: Int?
    public let elapsed_ms: Int?
    public let attempts: [Attempt]?
    public let played: Bool
    public let rank: Int?
    public let prev_rank: Int?
    // Migration 0008: the current window's counts and the previous window (yesterday for
    // period 'today'). Optional so rows from older fixtures still decode.
    public let solved_count: Int?
    public let played_count: Int?
    public let prev_score: Int?
    public let prev_played: Bool?
    public let prev_elapsed_ms: Int?
    public let prev_solved_count: Int?
    public let prev_played_count: Int?
    // Migration 0009: the member's current streak and avatar version (0 = no picture).
    public let streak: Int?
    public let avatar_version: Int?

    public init(user_id: String, display_name: String, score: Int, tries: Int? = nil,
                elapsed_ms: Int? = nil, attempts: [Attempt]? = nil, played: Bool,
                rank: Int? = nil, prev_rank: Int? = nil,
                solved_count: Int? = nil, played_count: Int? = nil,
                prev_score: Int? = nil, prev_played: Bool? = nil, prev_elapsed_ms: Int? = nil,
                prev_solved_count: Int? = nil, prev_played_count: Int? = nil,
                streak: Int? = nil, avatar_version: Int? = nil) {
        self.streak = streak
        self.avatar_version = avatar_version
        self.user_id = user_id
        self.display_name = display_name
        self.score = score
        self.tries = tries
        self.elapsed_ms = elapsed_ms
        self.attempts = attempts
        self.played = played
        self.rank = rank
        self.prev_rank = prev_rank
        self.solved_count = solved_count
        self.played_count = played_count
        self.prev_score = prev_score
        self.prev_played = prev_played
        self.prev_elapsed_ms = prev_elapsed_ms
        self.prev_solved_count = prev_solved_count
        self.prev_played_count = prev_played_count
    }
}

public struct Circle: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let code: String
    public let name: String
    public let owner_id: String
}

public struct Reaction: Codable, Sendable, Equatable {
    public let from_user: String
    public let to_user: String
    public let puzzle_date: String
    public let emoji: String
}

public struct Taunt: Codable, Sendable, Equatable {
    public let user_id: String
    public let puzzle_date: String
    public let text: String
}

/// The caller's own `users` row (only client-readable columns).
public struct Profile: Codable, Sendable, Equatable {
    public let id: String
    public var display_name: String
    public var tz: String
    public var discoverable: Bool
    public let invite_code: String
    public var push_daily: Bool
    public var push_daily_at: String   // "HH:MM:SS" as PostgREST renders `time`
    public var push_streak: Bool
    public var push_passed: Bool
    /// Migration 0009: 0 = no picture; bumped on every upload so image caches refresh.
    /// Optional so profiles fetched before the column existed still decode.
    public var avatar_version: Int?
}

/// One row of `list_items` for a puzzle the caller has already played: the value the
/// puzzle ordered by, plus the one-line fact shown on the results reveal strip.
public struct RevealItem: Codable, Sendable, Equatable {
    public let id: Int
    public let label: String
    public let value: Double
    public let fact: String?
    public init(id: Int, label: String, value: Double, fact: String?) {
        self.id = id
        self.label = label
        self.value = value
        self.fact = fact
    }
}

/// A past result row as read from `results` for the heatmap and stats.
public struct ResultSummary: Codable, Sendable, Equatable {
    public let puzzle_date: String
    public let tries: Int
    public let solved: Bool
    public let score: Int
    /// Optional so older fixtures decode; the hub shows this instead of points.
    public let elapsed_ms: Int?

    public init(puzzle_date: String, tries: Int, solved: Bool, score: Int, elapsed_ms: Int? = nil) {
        self.puzzle_date = puzzle_date
        self.tries = tries
        self.solved = solved
        self.score = score
        self.elapsed_ms = elapsed_ms
    }
}

// MARK: Enumerations shared with the server

public enum BoardKind: String, Sendable, Codable { case friends, circle, everyone }
public enum BoardPeriod: String, Sendable, Codable { case today, week, all }

/// The six allowed reactions, in display order.
public let reactionEmoji: [String] = ["🔥", "👏", "😂", "😭", "🫡", "🙄"]
