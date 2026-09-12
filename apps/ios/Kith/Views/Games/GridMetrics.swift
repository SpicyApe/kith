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

/// Twelve muted region fills plus a distinct glyph each, so Stars is readable with
/// `accessibilityDifferentiateWithoutColor` on and in dark mode (the tints are system
/// colours, so they adapt).
enum RegionStyle {
    static let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .brown,
    ]

    static let symbols: [String] = [
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
        "hexagon.fill", "seal.fill", "capsule.fill", "rhombus.fill",
        "octagon.fill", "pentagon.fill", "heart.fill", "moon.fill",
    ]

    static func color(_ region: Int) -> Color {
        colors[((region % colors.count) + colors.count) % colors.count].opacity(0.28)
    }

    static func symbol(_ region: Int) -> String {
        symbols[((region % symbols.count) + symbols.count) % symbols.count]
    }
}

extension GridPoint {
    /// "row 3 column 5" — VoiceOver reads cells in human 1-based numbering, while the
    /// accessibility *identifiers* stay on the engine's 0-based coordinates.
    var spokenPosition: String { "row \(row + 1) column \(col + 1)" }
}
