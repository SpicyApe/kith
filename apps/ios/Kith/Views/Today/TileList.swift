// TileList.swift — the five tiles. Green = locked, a single 600 ms yellow pulse for
// "one position off", grey otherwise (docs/03 §2).

import LineupEngine
import Foundation
import SwiftUI
import UIKit

/// The only haptics in the app. `UIFeedbackGenerator` is main-actor only.
@MainActor
enum Haptics {
    static func solved() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func partial() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func failed() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

@MainActor
struct TileList: View {
    let engine: LineupEngine
    /// Positions that should pulse yellow right now.
    let nearPositions: Set<Int>
    let onMove: (IndexSet, Int) -> Void

    private var labels: [Int: String] {
        var map: [Int: String] = [:]
        for item in engine.puzzle.items { map[item.id] = item.label }
        return map
    }

    var body: some View {
        let locked = engine.lockedPositions
        let names = labels

        List {
            ForEach(Array(engine.currentOrder.enumerated()), id: \.element) { index, itemId in
                TileRow(
                    label: names[itemId] ?? "",
                    position: index,
                    isLocked: locked.contains(index),
                    isNear: nearPositions.contains(index)
                )
                .moveDisabled(locked.contains(index))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .environment(\.editMode, .constant(.active))
        .accessibilityLabel("Puzzle tiles. Drag to reorder.")
    }
}

@MainActor
private struct TileRow: View {
    let label: String
    let position: Int
    let isLocked: Bool
    let isNear: Bool

    @State private var pulsing = false

    private var background: Color {
        if isLocked { return .tileCorrect }
        return pulsing ? .tileNear : .tileNeutral
    }

    private var stateDescription: String {
        if isLocked { return "correct, locked" }
        if isNear { return "one position off" }
        return "not placed yet"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position + 1)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)

            Text(label)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            // The drag handle is drawn by the List in edit mode; locked rows lose it,
            // so a lock glyph keeps the row from looking empty.
            Image(systemName: isLocked ? "lock.fill" : "line.3.horizontal")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .opacity(isLocked ? 1 : 0)
                .frame(width: 18)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Position \(position + 1): \(label), \(stateDescription)")
        .task(id: isNear) {
            guard isNear else { return }
            pulsing = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            pulsing = false
        }
    }
}
