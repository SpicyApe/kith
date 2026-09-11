// MovementChip.swift — "▲2" / "▼1" / "–" / "NEW". Text comes from KithCore.

import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct MovementChip: View {
    let movement: RankMovement

    private var color: Color {
        switch movement {
        case .up: return .green
        case .down: return .red
        case .same: return .secondary
        case .new: return .kithAccent
        case .none: return .clear
        }
    }

    private var accessibilityText: String {
        switch movement {
        case .up(let n): return "up \(n) place\(n == 1 ? "" : "s")"
        case .down(let n): return "down \(n) place\(n == 1 ? "" : "s")"
        case .same: return "unchanged"
        case .new: return "new"
        case .none: return ""
        }
    }

    var body: some View {
        if movement == .none {
            EmptyView()
        } else {
            Text(movement.chipText)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
                .accessibilityLabel(accessibilityText)
        }
    }
}
