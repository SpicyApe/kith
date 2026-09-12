// Trail.swift — Zip-style: one path through every cell, waypoints in order. CONTRACT FILE.

import Foundation

/// Wire format: `{ "n": 6, "waypoints": [[r,c],...] }`; waypoint i+1 is at index i.
public struct TrailSpec: Codable, Sendable, Equatable {
    public let n: Int
    public let waypoints: [[Int]]
    public init(n: Int, waypoints: [[Int]]) {
        self.n = n
        self.waypoints = waypoints
    }
}

public struct TrailEngine: Sendable, Equatable {
    public let spec: TrailSpec
    /// Cells in visiting order; always starts with waypoint 1.
    public private(set) var path: [GridPoint]

    /// Validates: 3 ≤ n ≤ 9, at least two waypoints, each a 2-int in-range pair, all distinct.
    /// Throws `GridError.invalidSpec`. The initial path is `[waypoint 1]`.
    public init(spec: TrailSpec) throws {
        let n = spec.n
        guard n >= 3, n <= 9 else {
            throw GridError.invalidSpec("n out of range")
        }
        guard spec.waypoints.count >= 2 else {
            throw GridError.invalidSpec("need at least two waypoints")
        }
        var points: [GridPoint] = []
        var seen = Set<GridPoint>()
        for waypoint in spec.waypoints {
            guard waypoint.count == 2 else {
                throw GridError.invalidSpec("waypoint shape")
            }
            let r = waypoint[0]
            let c = waypoint[1]
            guard r >= 0, r < n, c >= 0, c < n else {
                throw GridError.invalidSpec("waypoint out of range")
            }
            let point = GridPoint(row: r, col: c)
            guard !seen.contains(point) else {
                throw GridError.invalidSpec("waypoints must be distinct")
            }
            seen.insert(point)
            points.append(point)
        }
        self.spec = spec
        self.path = [points[0]]
    }

    private var waypointPoints: [GridPoint] {
        spec.waypoints.map { GridPoint(row: $0[0], col: $0[1]) }
    }

    /// The waypoint number (1-based) at a cell, or nil.
    public func waypointNumber(at point: GridPoint) -> Int? {
        let points = waypointPoints
        for (index, waypoint) in points.enumerated() where waypoint == point {
            return index + 1
        }
        return nil
    }

    /// The next waypoint number the path must reach (2 after start; `spec.waypoints.count + 1` once all are visited).
    public var nextWaypoint: Int {
        let points = waypointPoints
        for (index, waypoint) in points.enumerated() where !path.contains(waypoint) {
            return index + 1
        }
        return points.count + 1
    }

    public var visited: Set<GridPoint> {
        Set(path)
    }

    /// Extends the path by one cell. Returns false (and leaves the path unchanged) when the cell
    /// is out of bounds, not orthogonally adjacent to the path's last cell, already visited, or a
    /// waypoint other than the next required one. If the cell is the previous cell in the path
    /// (dragging backwards), retracts one step instead and returns true.
    @discardableResult
    public mutating func extend(to point: GridPoint) -> Bool {
        let n = spec.n
        guard point.row >= 0, point.row < n, point.col >= 0, point.col < n else {
            return false
        }
        if path.count >= 2, point == path[path.count - 2] {
            path.removeLast()
            return true
        }
        guard let last = path.last, last.isOrthogonallyAdjacent(to: point) else {
            return false
        }
        guard !visited.contains(point) else {
            return false
        }
        if let waypointNum = waypointNumber(at: point), waypointNum != nextWaypoint {
            return false
        }
        path.append(point)
        return true
    }

    /// Truncates the path so that `point` is its last cell; no-op if the point is not on the path.
    /// The first cell can never be removed.
    public mutating func retract(to point: GridPoint) {
        guard let index = path.firstIndex(of: point) else { return }
        path.removeSubrange((index + 1)...)
    }

    public mutating func reset() {
        path = [path[0]]
    }

    /// Path covers all n² cells and ends on the last waypoint (waypoint order is enforced by `extend`).
    public var isComplete: Bool {
        let n = spec.n
        guard path.count == n * n else { return false }
        return path.last == waypointPoints.last
    }

    /// `[[r,c], ...]` when complete, else nil. Sent as `{ "path": ... }`.
    public var answer: [[Int]]? {
        guard isComplete else { return nil }
        return path.map { [$0.row, $0.col] }
    }

    /// Mirrors `trailShareRows`: a single row of 🟩 repeated once per waypoint.
    public func shareRows() -> [String] {
        [String(repeating: "🟩", count: spec.waypoints.count)]
    }
}
