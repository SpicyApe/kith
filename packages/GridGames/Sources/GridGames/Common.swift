// Common.swift — shared types, scoring and share text for the grid games.
//
// CONTRACT FILE: public declarations and doc comments are frozen; implementers fill
// `fatalError("implement")` bodies and may add internal helpers. No Foundation beyond
// what is imported here; no I/O; no randomness (generation is server-side).

import Foundation

public enum GameKind: String, Codable, Sendable, CaseIterable, Equatable {
    case stars, duo, trail

    /// "Stars", "Duo", "Trail".
    public var title: String {
        switch self {
        case .stars: return "Stars"
        case .duo: return "Duo"
        case .trail: return "Trail"
        }
    }

    /// SF Symbol name for the hub row: stars "star.fill", duo "circle.lefthalf.filled", trail "point.topleft.down.to.point.bottomright.curvepath".
    public var symbolName: String {
        switch self {
        case .stars: return "star.fill"
        case .duo: return "circle.lefthalf.filled"
        case .trail: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

public struct GridPoint: Hashable, Codable, Sendable, Equatable {
    public let row: Int
    public let col: Int
    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
    /// True when the other point is orthogonally adjacent (Manhattan distance 1).
    public func isOrthogonallyAdjacent(to other: GridPoint) -> Bool {
        let dr = abs(row - other.row)
        let dc = abs(col - other.col)
        return (dr == 1 && dc == 0) || (dr == 0 && dc == 1)
    }
    /// True when the other point is within one step in any direction (including diagonal), excluding itself.
    public func touches(_ other: GridPoint) -> Bool {
        if self == other { return false }
        let dr = abs(row - other.row)
        let dc = abs(col - other.col)
        return dr <= 1 && dc <= 1
    }
}

/// Mirrors `scoreFor` in supabase/functions/_shared/games/common.ts.
public enum GameScoring {
    /// `gaveUp` → 100; else `max(100, 1000 − 2 × min(elapsedMs / 1000, 450))` with integer division; negative elapsed → 0.
    public static func score(elapsedMs: Int, gaveUp: Bool) -> Int {
        if gaveUp { return 100 }
        let ms = elapsedMs > 0 ? elapsedMs : 0
        let seconds = min(ms / 1000, 450)
        return max(100, 1000 - 2 * seconds)
    }
}

/// Mirrors `gameShareText` in common.ts, exactly:
///
///     Kith Stars #12 · 1:23
///     <rows…>
///     kith.app/g/stars/12?r=7F3Q
///
/// The second line item is `· gave up` instead of the time when `gaveUp`. Time is
/// `elapsedMs / 1000` as m:ss (seconds zero-padded, minutes not). `rows` may be empty.
/// `?r=` only when refCode is non-nil and non-empty. Joined with "\n", no trailing newline.
public enum GameShareText {
    public static func render(game: GameKind, number: Int, elapsedMs: Int, gaveUp: Bool,
                              rows: [String], refCode: String?) -> String {
        let suffix: String
        if gaveUp {
            suffix = "gave up"
        } else {
            let ms = elapsedMs > 0 ? elapsedMs : 0
            let totalSeconds = ms / 1000
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            let secondsStr = seconds < 10 ? "0\(seconds)" : "\(seconds)"
            suffix = "\(minutes):\(secondsStr)"
        }

        var lines = ["Kith \(game.title) #\(number) · \(suffix)"]
        lines.append(contentsOf: rows)
        var link = "kith.app/g/\(game.rawValue)/\(number)"
        if let refCode, !refCode.isEmpty {
            link += "?r=\(refCode)"
        }
        lines.append(link)
        return lines.joined(separator: "\n")
    }
}

public enum GridError: Error, Equatable, Sendable {
    /// Spec failed validation; the string is a human-readable reason.
    case invalidSpec(String)
    case outOfBounds
}
