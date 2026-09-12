// StarsView.swift — Queens-style grid (docs/07 §"Stars").
//
// Tap cycles empty → ✕ → ★ → empty; dragging paints ✕ across empty cells. Conflicting
// stars get a red ring as well as the colour, and every region carries a glyph so the
// board is readable with `accessibilityDifferentiateWithoutColor` on.

import Foundation
import GridGames
import KithCore
import SwiftUI

@MainActor
struct StarsView: View {
    let engine: StarsEngine

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cell the finger is currently over, and whether this gesture has become a drag.
    @State private var dragCell: GridPoint?
    @State private var didDrag = false

    private var conflicts: Set<GridPoint> { engine.conflicts }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let metrics = GridMetrics(size: engine.spec.n,
                                      spacing: GridMetrics.spacing(for: engine.spec.n, base: 2),
                                      side: side)

            board(metrics)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: model.activeGame?.moves ?? 0)
        .sensoryFeedback(.warning, trigger: model.activeGame?.mistakes ?? 0)
        .sensoryFeedback(.success, trigger: engine.isComplete)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stars grid, \(engine.spec.n) by \(engine.spec.n)")
    }

    private func board(_ metrics: GridMetrics) -> some View {
        VStack(spacing: metrics.spacing) {
            ForEach(0..<engine.spec.n, id: \.self) { row in
                HStack(spacing: metrics.spacing) {
                    ForEach(0..<engine.spec.n, id: \.self) { column in
                        cell(GridPoint(row: row, col: column), metrics: metrics)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(gesture(metrics))
    }

    private func cell(_ point: GridPoint, metrics: GridMetrics) -> some View {
        let region = engine.spec.regions[point.row][point.col]
        let mark = engine.marks[point.row][point.col]
        let isConflicting = mark == .star && conflicts.contains(point)

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(RegionStyle.color(region))

            if differentiateWithoutColor {
                Image(systemName: RegionStyle.symbol(region))
                    .font(.system(size: max(8, metrics.cell * 0.22)))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(3)
            }

            switch mark {
            case .empty:
                EmptyView()
            case .cross:
                Image(systemName: "xmark")
                    .font(.system(size: max(9, metrics.cell * 0.34), weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.35))
            case .star:
                Image(systemName: "star.fill")
                    .font(.system(size: max(11, metrics.cell * 0.52)))
                    .foregroundStyle(isConflicting ? Color.red : Color.primary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isConflicting ? Color.red : Color.primary.opacity(0.12),
                              lineWidth: isConflicting ? 2.5 : 0.5)
        )
        .frame(width: metrics.cell, height: metrics.cell)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: mark)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(point.spokenPosition), \(Self.spoken(mark, conflicting: isConflicting))")
        .accessibilityIdentifier("stars.cell.\(point.row).\(point.col)")
    }

    private static func spoken(_ mark: StarsMark, conflicting: Bool) -> String {
        switch mark {
        case .empty: return "empty"
        case .cross: return "marked out"
        case .star: return conflicting ? "star, conflicting" : "star"
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
                // The gesture only becomes a paint stroke once it leaves the first cell;
                // the first cell is then painted too, so the stroke starts where it looks
                // like it started.
                if !didDrag {
                    didDrag = true
                    model.starsPaintCross(at: current)
                }
                dragCell = point
                model.starsPaintCross(at: point)
            }
            .onEnded { value in
                let point = metrics.point(at: value.location) ?? dragCell
                if !didDrag, let point {
                    model.starsCycle(at: point)
                }
                dragCell = nil
                didDrag = false
            }
    }
}
