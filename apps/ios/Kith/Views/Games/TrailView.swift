// TrailView.swift — Zip-style path drawing (docs/07 §"Trail", docs/08 §"Trail").
//
// A single `DragGesture(minimumDistance: 0)` on the grid maps the touch to a cell and
// calls `extend(to:)` as the finger crosses cell centres; dragging back retracts. Tapping
// a cell already on the path retracts to it. The path is drawn under the waypoint discs, in
// `Theme.trail`, through the cell centres, with a slightly larger end dot; visited cells get
// a light `trail` wash and the next required waypoint carries a ring.

import Foundation
import GridGames
import KithCore
import SwiftUI

@MainActor
struct TrailView: View {
    let engine: TrailEngine

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragCell: GridPoint?
    @State private var didDrag = false
    /// Drives the short scale bounce once the path completes (skipped under Reduce Motion).
    @State private var bounceScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let metrics = GridMetrics(size: engine.spec.n, spacing: 0, side: side)

            board(metrics)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: model.activeGames[.trail]?.moves ?? 0)
        .sensoryFeedback(.success, trigger: engine.isComplete)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trail grid, \(engine.spec.n) by \(engine.spec.n)")
        .accessibilityValue(pathSummary)
    }

    /// PLAN-games.md: "the path in Trail has a summary label (\"path 12 of 36 cells\")".
    private var pathSummary: String {
        "path \(engine.path.count) of \(engine.spec.n * engine.spec.n) cells"
    }

    private func board(_ metrics: GridMetrics) -> some View {
        ZStack {
            cellsBackground(metrics)
            metrics.lineOverlay()
            pathShape(metrics)
                .allowsHitTesting(false)
            waypointOverlay(metrics)
        }
        .gridBoardChrome()
        .contentShape(Rectangle())
        .gesture(gesture(metrics))
    }

    private func cellsBackground(_ metrics: GridMetrics) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<engine.spec.n, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<engine.spec.n, id: \.self) { column in
                        cell(GridPoint(row: row, col: column), metrics: metrics)
                    }
                }
            }
        }
    }

    private func cell(_ point: GridPoint, metrics: GridMetrics) -> some View {
        let waypoint = engine.waypointNumber(at: point)
        let onPath = engine.visited.contains(point)
        let isNext = waypoint != nil && waypoint == engine.nextWaypoint

        return ZStack {
            Theme.paper

            if onPath {
                Theme.trail.opacity(0.14)
            }

            if isNext {
                SwiftUI.Circle()
                    .strokeBorder(Theme.trail, lineWidth: 2.5)
                    .frame(width: metrics.cell * 0.76, height: metrics.cell * 0.76)
            }
        }
        .frame(width: metrics.cell, height: metrics.cell)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(point.spokenPosition), \(Self.spoken(waypoint: waypoint, onPath: onPath))")
        .accessibilityIdentifier("trail.cell.\(point.row).\(point.col)")
    }

    /// The waypoint discs and their numbers, drawn above the path (finding B4) — previously
    /// part of `cell(_:metrics:)`, they sat under `pathShape` in the old single `ZStack` and
    /// so could be covered by the drawn line.
    private func waypointOverlay(_ metrics: GridMetrics) -> some View {
        ZStack {
            ForEach(0..<engine.spec.n, id: \.self) { row in
                ForEach(0..<engine.spec.n, id: \.self) { column in
                    let point = GridPoint(row: row, col: column)
                    if let waypoint = engine.waypointNumber(at: point) {
                        Text("\(waypoint)")
                            .font(.system(size: max(10, metrics.cell * 0.4), weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .frame(width: metrics.cell * 0.66, height: metrics.cell * 0.66)
                            .background(SwiftUI.Circle().fill(Theme.ink))
                            .position(metrics.centre(of: point))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func spoken(waypoint: Int?, onPath: Bool) -> String {
        var parts: [String] = []
        if let waypoint { parts.append("waypoint \(waypoint)") }
        parts.append(onPath ? "on the path" : "empty")
        return parts.joined(separator: ", ")
    }

    /// The polyline through the visited cell centres, drawn under the waypoint discs.
    private func pathShape(_ metrics: GridMetrics) -> some View {
        let points = engine.path.map(metrics.centre)
        let width = max(3, metrics.cell * 0.42)
        let endDot = max(width, metrics.cell * 0.5)

        return ZStack {
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(Theme.trail, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

            if let last = points.last {
                SwiftUI.Circle()
                    .fill(Theme.trail)
                    .frame(width: endDot, height: endDot)
                    .position(last)
            }
        }
        // Below full strength normally; completion animates the whole path up to 100%
        // opacity with a short scale bounce (skipped under Reduce Motion).
        .opacity(engine.isComplete ? 1 : 0.82)
        .scaleEffect(bounceScale)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: engine.path)
        .onChange(of: engine.isComplete) { _, complete in
            guard complete, !reduceMotion else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                bounceScale = 1.06
            }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6).delay(0.14)) {
                bounceScale = 1.0
            }
        }
    }

    // MARK: Gesture

    private func gesture(_ metrics: GridMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let point = metrics.point(at: value.location) else { return }
                guard let current = dragCell else {
                    dragCell = point
                    return
                }
                guard point != current else { return }
                didDrag = true
                dragCell = point
                // `extend` itself refuses non-adjacent, visited and out-of-order cells, and
                // treats a step back onto the previous cell as a retraction.
                model.trailExtend(to: point)
            }
            .onEnded { value in
                let point = metrics.point(at: value.location) ?? dragCell
                if !didDrag, let point {
                    if engine.visited.contains(point) {
                        model.trailRetract(to: point)
                    } else {
                        model.trailExtend(to: point)
                    }
                }
                dragCell = nil
                didDrag = false
            }
    }
}
