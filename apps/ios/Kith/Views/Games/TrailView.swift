// TrailView.swift — Zip-style path drawing (docs/07 §"Trail").
//
// A single `DragGesture(minimumDistance: 0)` on the grid maps the touch to a cell and
// calls `extend(to:)` as the finger crosses cell centres; dragging back retracts. Tapping
// a cell already on the path retracts to it. The path is drawn as a rounded polyline
// through the cell centres, over the grid, in the accent colour.

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

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let metrics = GridMetrics(size: engine.spec.n,
                                      spacing: GridMetrics.spacing(for: engine.spec.n, base: 3),
                                      side: side)

            board(metrics)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: model.activeGame?.moves ?? 0)
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
            VStack(spacing: metrics.spacing) {
                ForEach(0..<engine.spec.n, id: \.self) { row in
                    HStack(spacing: metrics.spacing) {
                        ForEach(0..<engine.spec.n, id: \.self) { column in
                            cell(GridPoint(row: row, col: column), metrics: metrics)
                        }
                    }
                }
            }
            pathShape(metrics)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(gesture(metrics))
    }

    private func cell(_ point: GridPoint, metrics: GridMetrics) -> some View {
        let waypoint = engine.waypointNumber(at: point)
        let onPath = engine.visited.contains(point)

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.tileNeutral)

            if let waypoint {
                Text("\(waypoint)")
                    .font(.system(size: max(10, metrics.cell * 0.4), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .frame(width: metrics.cell * 0.62, height: metrics.cell * 0.62)
                    .background(SwiftUI.Circle().fill(Color.kithAccent))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .frame(width: metrics.cell, height: metrics.cell)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(point.spokenPosition), \(Self.spoken(waypoint: waypoint, onPath: onPath))")
        .accessibilityIdentifier("trail.cell.\(point.row).\(point.col)")
    }

    private static func spoken(waypoint: Int?, onPath: Bool) -> String {
        var parts: [String] = []
        if let waypoint { parts.append("waypoint \(waypoint)") }
        parts.append(onPath ? "on the path" : "empty")
        return parts.joined(separator: ", ")
    }

    /// The polyline through the visited cell centres.
    private func pathShape(_ metrics: GridMetrics) -> some View {
        let points = engine.path.map(metrics.centre)
        return Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(
            Color.kithAccent.opacity(0.7),
            style: StrokeStyle(lineWidth: max(4, metrics.cell * 0.28), lineCap: .round, lineJoin: .round)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: engine.path)
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
