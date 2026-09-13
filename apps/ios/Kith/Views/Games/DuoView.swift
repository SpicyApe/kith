// DuoView.swift — Tango-style 6×6 binary grid (docs/07 §"Duo", docs/08 §"Duo").
//
// Givens have a filled background and are not tappable; everything else cycles
// empty → ● → ◆ → empty. `=` and `×` badges sit on the shared edge of a constrained pair,
// and cells in violation get a red wash and ring, never colour alone. The two marks differ
// by shape and colour, so they read distinctly for a deuteranopia player.

import Foundation
import GridGames
import KithCore
import SwiftUI

@MainActor
struct DuoView: View {
    let engine: DuoEngine

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var conflicts: Set<GridPoint> { engine.conflicts }

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
        .sensoryFeedback(.selection, trigger: model.activeGames[.duo]?.moves ?? 0)
        .sensoryFeedback(.warning, trigger: model.activeGames[.duo]?.mistakes ?? 0)
        .sensoryFeedback(.success, trigger: engine.isComplete)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Duo grid, 6 by 6")
    }

    private func board(_ metrics: GridMetrics) -> some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<engine.spec.n, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<engine.spec.n, id: \.self) { column in
                            cell(GridPoint(row: row, col: column), metrics: metrics)
                        }
                    }
                }
            }
            metrics.lineOverlay()
            badges(metrics)
        }
        .gridBoardChrome()
    }

    private func cell(_ point: GridPoint, metrics: GridMetrics) -> some View {
        let value = engine.cells[point.row][point.col]
        let given = engine.isGiven(at: point)
        let isConflicting = conflicts.contains(point)
        let fill = isConflicting ? Theme.dangerWash : (given ? Theme.paperMuted : Theme.paper)

        return Button {
            model.duoCycle(at: point)
        } label: {
            ZStack {
                fill

                if let value {
                    if value == 0 {
                        Image(systemName: "circle.fill")
                            .font(.system(size: max(10, metrics.cell * 0.52)))
                            .foregroundStyle(Theme.duo)
                    } else {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: max(10, metrics.cell * 0.52)))
                            .foregroundStyle(Theme.duoAlt)
                    }
                }

                if isConflicting {
                    Rectangle()
                        .strokeBorder(Theme.danger, lineWidth: 2)
                }
            }
            .frame(width: metrics.cell, height: metrics.cell)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(given)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(point.spokenPosition), \(Self.spoken(value, given: given, conflicting: isConflicting))")
        .accessibilityIdentifier("duo.cell.\(point.row).\(point.col)")
    }

    private static func spoken(_ value: Int?, given: Bool, conflicting: Bool) -> String {
        var text: String
        switch value {
        case .some(0): text = given ? "given amber circle" : "amber circle"
        case .some: text = given ? "given indigo diamond" : "indigo diamond"
        default: text = "empty"
        }
        if conflicting { text += ", conflicting" }
        return text
    }

    // MARK: Constraint badges

    /// One badge per `eq` / `ne` pair, centred on the edge the two cells share.
    private func badges(_ metrics: GridMetrics) -> some View {
        ZStack {
            ForEach(Array(engine.spec.eq.enumerated()), id: \.offset) { _, pair in
                badge(pair, symbol: "equal", label: "same", metrics: metrics)
            }
            ForEach(Array(engine.spec.ne.enumerated()), id: \.offset) { _, pair in
                badge(pair, symbol: "xmark", label: "different", metrics: metrics)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func badge(_ pair: [Int], symbol: String, label: String, metrics: GridMetrics) -> some View {
        if pair.count == 4 {
            let a = metrics.centre(of: GridPoint(row: pair[0], col: pair[1]))
            let b = metrics.centre(of: GridPoint(row: pair[2], col: pair[3]))
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 20, height: 20)
                .background(
                    // `SwiftUI.Circle`, because this file also imports `KithCore.Circle`.
                    SwiftUI.Circle()
                        .fill(Theme.paper)
                        .overlay(SwiftUI.Circle().strokeBorder(Theme.ink.opacity(0.3), lineWidth: 1))
                )
                .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                .accessibilityHidden(true)
        }
    }
}
