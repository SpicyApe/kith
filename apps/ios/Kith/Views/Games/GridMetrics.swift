// GridMetrics.swift — the geometry and the region palette the three grid games share.

import Foundation
import GridGames
import SwiftUI

/// Maps a square grid onto a square of `side` points and back again.
///
/// The grids deliberately do NOT live inside a `ScrollView` (PLAN-games.md HIG checklist):
/// a drag gesture inside one fights the scroll, and a square that fills the width minus the
/// screen's 32 pt of padding always fits without scrolling.
struct GridMetrics: Equatable {
    let size: Int
    let spacing: CGFloat
    let side: CGFloat

    /// Edge length of one cell.
    var cell: CGFloat {
        guard size > 0 else { return 0 }
        let gaps = spacing * CGFloat(size - 1)
        return max(1, (side - gaps) / CGFloat(size))
    }

    /// Distance from one cell's leading edge to the next one's.
    var step: CGFloat { cell + spacing }

    /// Which cell a touch at `location` (in the grid's own coordinate space) landed on.
    func point(at location: CGPoint) -> GridPoint? {
        guard step > 0 else { return nil }
        let column = Int((location.x / step).rounded(.down))
        let row = Int((location.y / step).rounded(.down))
        guard row >= 0, row < size, column >= 0, column < size else { return nil }
        return GridPoint(row: row, col: column)
    }

    /// Centre of a cell, for drawing Trail's path.
    func centre(of point: GridPoint) -> CGPoint {
        CGPoint(x: CGFloat(point.col) * step + cell / 2,
                y: CGFloat(point.row) * step + cell / 2)
    }

    /// Trail can go up to 9×9. At that size `base` (2–3 pt everywhere else) eats enough of
    /// the fixed board width that cells shrink below a comfortable tap target, so the three
    /// grid views tighten to a single point of spacing from `n == 9` on (finding C6; see
    /// also `GameHostView.hostHorizontalPadding`, which narrows the host's own padding at
    /// the same threshold).
    static func spacing(for n: Int, base: CGFloat) -> CGFloat {
        n >= 9 ? 1 : base
    }
}

/// Twelve distinct glyphs, one per region, for the `accessibilityDifferentiateWithoutColor`
/// overlay (docs/08-visual-design.md). The opaque fills themselves live in `Theme.region(_:)`.
enum RegionStyle {
    static let symbols: [String] = [
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
        "hexagon.fill", "seal.fill", "capsule.fill", "rhombus.fill",
        "octagon.fill", "pentagon.fill", "heart.fill", "moon.fill",
    ]

    static func symbol(_ region: Int) -> String {
        symbols[((region % symbols.count) + symbols.count) % symbols.count]
    }
}

extension GridPoint {
    /// "row 3 column 5" — VoiceOver reads cells in human 1-based numbering, while the
    /// accessibility *identifiers* stay on the engine's 0-based coordinates.
    var spokenPosition: String { "row \(row + 1) column \(col + 1)" }
}

extension GridMetrics {
    /// The flush-cell line system all three grids share (docs/08-visual-design.md): a
    /// 0.75 pt `ink` line at 22% opacity between every pair of adjacent cells, thickened to
    /// 2.5 pt full-strength `ink` wherever `regions` says the two cells' regions differ.
    /// Stars passes its region map; Duo and Trail pass `nil` and get uniform thin dividers
    /// (no region lines). Drawn once, above the cells, so adjacent thin/thick edges never
    /// double up the way per-cell borders would.
    func lineOverlay(regions: [[Int]]? = nil) -> some View {
        let n = size
        let s = step
        let thin = Theme.ink.opacity(0.22)
        let thick = Theme.ink

        func differs(_ a: (Int, Int), _ b: (Int, Int)) -> Bool {
            guard let regions else { return false }
            return regions[a.0][a.1] != regions[b.0][b.1]
        }

        return Canvas { context, _ in
            guard n > 1 else { return }
            // Vertical edges, between column `col` and `col + 1`.
            for row in 0..<n {
                for col in 0..<(n - 1) {
                    let isThick = differs((row, col), (row, col + 1))
                    let x = CGFloat(col + 1) * s
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: CGFloat(row) * s))
                    path.addLine(to: CGPoint(x: x, y: CGFloat(row + 1) * s))
                    context.stroke(path, with: .color(isThick ? thick : thin), lineWidth: isThick ? 2.5 : 0.75)
                }
            }
            // Horizontal edges, between row `row` and `row + 1`.
            for row in 0..<(n - 1) {
                for col in 0..<n {
                    let isThick = differs((row, col), (row + 1, col))
                    let y = CGFloat(row + 1) * s
                    var path = Path()
                    path.move(to: CGPoint(x: CGFloat(col) * s, y: y))
                    path.addLine(to: CGPoint(x: CGFloat(col + 1) * s, y: y))
                    context.stroke(path, with: .color(isThick ? thick : thin), lineWidth: isThick ? 2.5 : 0.75)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// The board chrome shared by all three grids: 10 pt outer corners and a 2.5 pt `ink`
    /// border, applied around the flush cell stack (docs/08-visual-design.md).
    func gridBoardChrome() -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: Theme.boardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.boardRadius, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: 2.5)
            )
    }
}
