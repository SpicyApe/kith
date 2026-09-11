// MiniGrid.swift — five small squares showing someone's final attempt.

import LineupEngine
import Foundation
import SwiftUI
import UIKit

@MainActor
struct MiniGrid: View {
    let feedback: [TileFeedback]
    var square: CGFloat = 9

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(feedback.enumerated()), id: \.offset) { _, tile in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(for: tile))
                    .frame(width: square, height: square)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.describe(feedback))
    }

    private func color(for tile: TileFeedback) -> Color {
        switch tile {
        case .correct: return .green
        case .near: return .yellow
        case .wrong: return Color.secondary.opacity(0.35)
        }
    }

    static func describe(_ feedback: [TileFeedback]) -> String {
        guard !feedback.isEmpty else { return "" }
        let correct = feedback.filter { $0 == .correct }.count
        return "Final try: \(correct) of \(feedback.count) correct"
    }
}

/// The full grid (one row per attempt) used on the results screen.
@MainActor
struct AttemptGrid: View {
    let grid: [[TileFeedback]]
    var square: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(grid.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, tile in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(fill(for: tile))
                            .frame(width: square, height: square)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Try \(index + 1): \(MiniGrid.describe(row))")
            }
        }
    }

    private func fill(for tile: TileFeedback) -> Color {
        switch tile {
        case .correct: return .green
        case .near: return .yellow
        case .wrong: return Color.secondary.opacity(0.3)
        }
    }
}
