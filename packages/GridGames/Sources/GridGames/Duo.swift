// Duo.swift — Tango-style 6×6 binary grid. CONTRACT FILE.

import Foundation

/// Wire format: `{ "n": 6, "givens": [[null,0,...],...], "eq": [[r1,c1,r2,c2],...], "ne": [...] }`.
/// 0 = ●, 1 = ○. JSON `null` decodes to `nil`.
public struct DuoSpec: Codable, Sendable, Equatable {
    public let n: Int
    public let givens: [[Int?]]
    public let eq: [[Int]]
    public let ne: [[Int]]
    public init(n: Int, givens: [[Int?]], eq: [[Int]], ne: [[Int]]) {
        self.n = n
        self.givens = givens
        self.eq = eq
        self.ne = ne
    }
}

public struct DuoEngine: Sendable, Equatable {
    public let spec: DuoSpec
    /// nil = empty, 0 = ●, 1 = ○. Given cells always hold their given value.
    public private(set) var cells: [[Int?]]

    /// Validates: n == 6, givens is n×n with values in {0,1,nil}, each constraint has 4 ints in
    /// range describing orthogonally adjacent cells. Throws `GridError.invalidSpec`.
    public init(spec: DuoSpec) throws {
        guard spec.n == 6 else {
            throw GridError.invalidSpec("n must be 6")
        }
        let n = spec.n
        guard spec.givens.count == n else {
            throw GridError.invalidSpec("givens row count mismatch")
        }
        for row in spec.givens {
            guard row.count == n else {
                throw GridError.invalidSpec("givens column count mismatch")
            }
            for value in row {
                if let value, value != 0, value != 1 {
                    throw GridError.invalidSpec("given value out of range")
                }
            }
        }
        for constraint in spec.eq + spec.ne {
            guard constraint.count == 4 else {
                throw GridError.invalidSpec("constraint shape")
            }
            let (r1, c1, r2, c2) = (constraint[0], constraint[1], constraint[2], constraint[3])
            for value in [r1, c1, r2, c2] {
                guard value >= 0, value < n else {
                    throw GridError.invalidSpec("constraint out of range")
                }
            }
            let a = GridPoint(row: r1, col: c1)
            let b = GridPoint(row: r2, col: c2)
            guard a.isOrthogonallyAdjacent(to: b) else {
                throw GridError.invalidSpec("constraint not adjacent")
            }
        }
        self.spec = spec
        self.cells = spec.givens
    }

    public func isGiven(at point: GridPoint) -> Bool {
        spec.givens[point.row][point.col] != nil
    }

    private func checkBounds(_ point: GridPoint) throws {
        guard point.row >= 0, point.row < spec.n, point.col >= 0, point.col < spec.n else {
            throw GridError.outOfBounds
        }
    }

    /// empty → ● → ○ → empty. No-op on given cells. Throws `outOfBounds`.
    public mutating func cycle(at point: GridPoint) throws {
        try checkBounds(point)
        guard !isGiven(at: point) else { return }
        let current = cells[point.row][point.col]
        let next: Int?
        switch current {
        case .none: next = 0
        case .some(0): next = 1
        default: next = nil
        }
        cells[point.row][point.col] = next
    }

    public mutating func set(_ value: Int?, at point: GridPoint) throws {
        try checkBounds(point)
        guard !isGiven(at: point) else { return }
        cells[point.row][point.col] = value
    }

    /// Clears every non-given cell.
    public mutating func reset() {
        cells = spec.givens
    }

    /// Cells involved in a violation given the current (possibly partial) grid: any row or
    /// column with more than three of one symbol (all its filled cells), any three equal
    /// consecutive cells horizontally or vertically (those three), and both cells of a
    /// violated eq/ne constraint (only when both are filled).
    public var conflicts: Set<GridPoint> {
        let n = spec.n
        var result = Set<GridPoint>()

        for r in 0..<n {
            var zeros: [GridPoint] = []
            var ones: [GridPoint] = []
            for c in 0..<n {
                if let value = cells[r][c] {
                    if value == 0 { zeros.append(GridPoint(row: r, col: c)) }
                    else { ones.append(GridPoint(row: r, col: c)) }
                }
            }
            if zeros.count > 3 { result.formUnion(zeros) }
            if ones.count > 3 { result.formUnion(ones) }
        }
        for c in 0..<n {
            var zeros: [GridPoint] = []
            var ones: [GridPoint] = []
            for r in 0..<n {
                if let value = cells[r][c] {
                    if value == 0 { zeros.append(GridPoint(row: r, col: c)) }
                    else { ones.append(GridPoint(row: r, col: c)) }
                }
            }
            if zeros.count > 3 { result.formUnion(zeros) }
            if ones.count > 3 { result.formUnion(ones) }
        }

        for r in 0..<n {
            for c in 0..<(n - 2) {
                if let v = cells[r][c], cells[r][c + 1] == v, cells[r][c + 2] == v {
                    result.insert(GridPoint(row: r, col: c))
                    result.insert(GridPoint(row: r, col: c + 1))
                    result.insert(GridPoint(row: r, col: c + 2))
                }
            }
        }
        for c in 0..<n {
            for r in 0..<(n - 2) {
                if let v = cells[r][c], cells[r + 1][c] == v, cells[r + 2][c] == v {
                    result.insert(GridPoint(row: r, col: c))
                    result.insert(GridPoint(row: r + 1, col: c))
                    result.insert(GridPoint(row: r + 2, col: c))
                }
            }
        }

        for constraint in spec.eq {
            let a = GridPoint(row: constraint[0], col: constraint[1])
            let b = GridPoint(row: constraint[2], col: constraint[3])
            if let av = cells[a.row][a.col], let bv = cells[b.row][b.col], av != bv {
                result.insert(a)
                result.insert(b)
            }
        }
        for constraint in spec.ne {
            let a = GridPoint(row: constraint[0], col: constraint[1])
            let b = GridPoint(row: constraint[2], col: constraint[3])
            if let av = cells[a.row][a.col], let bv = cells[b.row][b.col], av == bv {
                result.insert(a)
                result.insert(b)
            }
        }

        return result
    }

    /// All cells filled and no conflicts (rows/columns then necessarily have three of each).
    public var isComplete: Bool {
        for row in cells {
            for value in row where value == nil {
                return false
            }
        }
        return conflicts.isEmpty
    }

    /// The 6×6 grid of 0/1 when complete, else nil. Sent as `{ "cells": ... }`.
    public var answer: [[Int]]? {
        guard isComplete else { return nil }
        return cells.map { row in row.map { $0! } }
    }

    /// Mirrors `duoShareRows`: one string per row, ● for 0, ○ for 1, using the current cells (complete).
    public func shareRows() -> [String] {
        cells.map { row in
            row.map { value -> String in
                value == nil ? "⬜️" : (value == 0 ? "●" : "○")
            }.joined()
        }
    }
}
