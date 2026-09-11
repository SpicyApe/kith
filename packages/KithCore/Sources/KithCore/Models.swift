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
}

// MARK: Enumerations shared with the server

public enum BoardKind: String, Sendable, Codable { case friends, circle, everyone }
public enum BoardPeriod: String, Sendable, Codable { case today, week, all }

/// The six allowed reactions, in display order.
public let reactionEmoji: [String] = ["🔥", "👏", "😂", "😭", "🫡", "🙄"]
