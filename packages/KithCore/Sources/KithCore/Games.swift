// Games.swift — client wire types for the games hub (docs/07-games-hub.md).
//
// CONTRACT FILE. Data types are complete; `GameSpec` / `GameAnswer` coding and the
// `SupabaseKithAPI` methods declared in KithAPI.swift are for implementers.

import Foundation
import GridGames

/// Which leaderboard column to show; mirrors `board(..., game_kind)`.
public enum BoardGame: String, Sendable, Codable, CaseIterable, Equatable {
    case lineup, stars, duo, trail, quint, total
}

/// Decoded from `start_game(d, g)`: `{ "date", "game", "number", "difficulty", "spec" }`.
public struct StartedGame: Decodable, Sendable, Equatable {
    public let date: String
    public let game: GameKind
    public let number: Int
    public let difficulty: String
    public let spec: GameSpec

    public init(date: String, game: GameKind, number: Int, difficulty: String, spec: GameSpec) {
        self.date = date
        self.game = game
        self.number = number
        self.difficulty = difficulty
        self.spec = spec
    }

    private enum CodingKeys: String, CodingKey {
        case date, game, number, difficulty, spec
    }

    /// Decodes `game` first, then `spec` into the matching GridGames spec type.
    /// Throws `DecodingError.dataCorrupted` when `spec` does not match the game.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(String.self, forKey: .date)
        let game = try container.decode(GameKind.self, forKey: .game)
        let number = try container.decode(Int.self, forKey: .number)
        let difficulty = try container.decode(String.self, forKey: .difficulty)

        let spec: GameSpec
        do {
            switch game {
            case .stars:
                spec = .stars(try container.decode(StarsSpec.self, forKey: .spec))
            case .duo:
                spec = .duo(try container.decode(DuoSpec.self, forKey: .spec))
            case .trail:
                spec = .trail(try container.decode(TrailSpec.self, forKey: .spec))
            case .quint:
                spec = .quint(try container.decode(QuintSpec.self, forKey: .spec))
            }
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath + [CodingKeys.spec],
                debugDescription: "spec does not match game \(game.rawValue)",
                underlyingError: error
            ))
        }

        self.date = date
        self.game = game
        self.number = number
        self.difficulty = difficulty
        self.spec = spec
    }
}

public enum GameSpec: Sendable, Equatable {
    case stars(StarsSpec)
    case duo(DuoSpec)
    case trail(TrailSpec)
    case quint(QuintSpec)

    public var kind: GameKind {
        switch self {
        case .stars: return .stars
        case .duo: return .duo
        case .trail: return .trail
        case .quint: return .quint
        }
    }
}

/// The `answer` field of a submit-game request. Encodes as `{"stars":[...]}`,
/// `{"cells":[[...]]}` or `{"path":[[r,c],...]}`.
public enum GameAnswer: Encodable, Sendable, Equatable {
    case stars([Int])
    case duo([[Int]])
    case trail([[Int]])
    /// Quint: the guesses made, lowercase, in order (docs/07 §Quint wire formats).
    case quint([String])

    private enum CodingKeys: String, CodingKey {
        case stars, cells, path, guesses
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stars(let cols):
            try container.encode(cols, forKey: .stars)
        case .duo(let cells):
            try container.encode(cells, forKey: .cells)
        case .trail(let path):
            try container.encode(path, forKey: .path)
        case .quint(let guesses):
            try container.encode(guesses, forKey: .guesses)
        }
    }
}

/// `submit-game` response `result`.
public struct StoredGameResult: Codable, Sendable, Equatable {
    public let date: String
    public let game: GameKind
    public let elapsedMs: Int
    public let elapsedSource: String
    public let mistakes: Int
    public let solved: Bool
    public let gaveUp: Bool
    public let score: Int
    public let submittedAt: String
}

public struct SubmitGameResponse: Codable, Sendable, Equatable {
    public let result: StoredGameResult
    public let streak: Int
}

/// A `game_results` row as read back for the hub and profile.
public struct GameResultSummary: Codable, Sendable, Equatable {
    public let date: String
    public let game: GameKind
    public let elapsed_ms: Int
    /// Wrong guesses for Quint (drives "Solved in k" and the `k/6` share progress); the
    /// grid games' mistake count otherwise.
    public let mistakes: Int
    public let solved: Bool
    public let gave_up: Bool
    public let score: Int
}

/// A `daily_games` row (client-readable columns) for the hub's list.
public struct DailyGameRow: Codable, Sendable, Equatable {
    public let date: String
    public let game: GameKind
    public let number: Int
    public let difficulty: String
}
