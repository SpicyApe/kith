// Stars.swift — Queens-style: one star per row, column and region; no two stars touch.
// CONTRACT FILE.

import Foundation

/// Wire format from `start_game(d, 'stars')`: `{ "n": 8, "regions": [[0,0,1,...],...] }`.
public struct StarsSpec: Codable, Sendable, Equatable {
    public let n: Int
    /// n×n region ids in 0..<n.
    public let regions: [[Int]]
    public init(n: Int, regions: [[Int]]) {
        self.n = n
        self.regions = regions
    }
}

public enum StarsMark: String, Codable, Sendable, Equatable {
    case empty, cross, star
}

/// Value-type state for one Stars puzzle.
public struct StarsEngine: Sendable, Equatable {
    public let spec: StarsSpec
    public private(set) var marks: [[StarsMark]]

    /// Validates: 4 ≤ n ≤ 12, `regions` is n×n, every id in 0..<n, every id present at least once.
    /// Throws `GridError.invalidSpec`. Starts with all cells `.empty`.
    public init(spec: StarsSpec) throws {
        let n = spec.n
        guard n >= 4, n <= 12 else {
            throw GridError.invalidSpec("n out of range")
        }
        guard spec.regions.count == n else {
            throw GridError.invalidSpec("regions row count mismatch")
        }
        var seen = Set<Int>()
        for row in spec.regions {
            guard row.count == n else {
                throw GridError.invalidSpec("regions column count mismatch")
            }
            for id in row {
                guard id >= 0, id < n else {
                    throw GridError.invalidSpec("region id out of range")
                }
                seen.insert(id)
            }
        }
        guard seen.count == n else {
            throw GridError.invalidSpec("not every region id present")
        }
        self.spec = spec
        self.marks = Array(repeating: Array(repeating: .empty, count: n), count: n)
    }

    private func checkBounds(_ point: GridPoint) throws {
        guard point.row >= 0, point.row < spec.n, point.col >= 0, point.col < spec.n else {
            throw GridError.outOfBounds
        }
    }

    /// empty → cross → star → empty. Throws `outOfBounds` for bad coordinates.
    public mutating func cycle(at point: GridPoint) throws {
        try checkBounds(point)
        let current = marks[point.row][point.col]
        let next: StarsMark
        switch current {
        case .empty: next = .cross
        case .cross: next = .star
        case .star: next = .empty
        }
        marks[point.row][point.col] = next
    }

    public mutating func set(_ mark: StarsMark, at point: GridPoint) throws {
        try checkBounds(point)
        marks[point.row][point.col] = mark
    }

    /// Clears every mark.
    public mutating func reset() {
        let n = spec.n
        marks = Array(repeating: Array(repeating: .empty, count: n), count: n)
    }

    public var starCount: Int {
        var count = 0
        for row in marks {
            for mark in row where mark == .star {
                count += 1
            }
        }
        return count
    }

    private var starPoints: [GridPoint] {
        var points: [GridPoint] = []
        for r in 0..<spec.n {
            for c in 0..<spec.n where marks[r][c] == .star {
                points.append(GridPoint(row: r, col: c))
            }
        }
        return points
    }

    /// Stars that violate a rule: another star in the same row, column or region, or a touching star (8-neighbourhood).
    public var conflicts: Set<GridPoint> {
        let stars = starPoints
        var result = Set<GridPoint>()
        for i in 0..<stars.count {
            for j in 0..<stars.count where i != j {
                let a = stars[i]
                let b = stars[j]
                if a.row == b.row || a.col == b.col
                    || spec.regions[a.row][a.col] == spec.regions[b.row][b.col]
                    || a.touches(b) {
                    result.insert(a)
                }
            }
        }
        return result
    }

    /// Exactly n stars, no conflicts, one per row, column and region.
    public var isComplete: Bool {
        let n = spec.n
        guard starCount == n else { return false }
        guard conflicts.isEmpty else { return false }
        let stars = starPoints
        let rows = Set(stars.map { $0.row })
        let cols = Set(stars.map { $0.col })
        let regions = Set(stars.map { spec.regions[$0.row][$0.col] })
        return rows.count == n && cols.count == n && regions.count == n
    }

    /// `stars[row] = column` when complete, else nil. This is the `answer` sent to submit-game.
    public var answer: [Int]? {
        guard isComplete else { return nil }
        var result = Array(repeating: -1, count: spec.n)
        for point in starPoints {
            result[point.row] = point.col
        }
        return result
    }

    /// Mirrors `starsShareRows`: one string per row, ⭐️ at the star's column, ⬛️ elsewhere, using the current stars.
    public func shareRows() -> [String] {
        var rows: [String] = []
        for r in 0..<spec.n {
            var starCol: Int? = nil
            for c in 0..<spec.n where marks[r][c] == .star {
                starCol = c
                break
            }
            var line = ""
            for c in 0..<spec.n {
                line += (starCol == c) ? "⭐️" : "⬛️"
            }
            rows.append(line)
        }
        return rows
    }
}
