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

    /// Drag-to-reorder needs edit mode, but a `Button` inside an editing row does not
    /// reliably receive taps, and the UI tests reorder with the ▲/▼ pair instead of
    /// dragging (TESTING.md §1). So whenever the test controls are on — `-uiTesting`
    /// or `-uiTestingControls` (§7) — the list leaves edit mode.
    private var listEditMode: EditMode {
        #if DEBUG
        return UITesting.controlsActive ? .inactive : .active
        #else
        return .active
        #endif
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
                    isNear: nearPositions.contains(index),
                    // SwiftUI's `.onMove` coordinates are "insert before", so one step
                    // down is `position + 2` and one step up is `position - 1`.
                    onMoveUp: { onMove(IndexSet(integer: index), index - 1) },
                    onMoveDown: { onMove(IndexSet(integer: index), index + 2) }
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
        .environment(\.editMode, .constant(listEditMode))
        .accessibilityLabel("Puzzle tiles. Drag to reorder.")
    }
}

@MainActor
private struct TileRow: View {
    let label: String
    let position: Int
    let isLocked: Bool
    let isNear: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

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
        // The tile itself is one combined accessibility element; the ▲/▼ pair sits
        // outside it so each button stays separately addressable.
        HStack(spacing: 8) {
            tile
            moveButtons
        }
        .task(id: isNear) {
            guard isNear else { return }
            pulsing = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            pulsing = false
        }
    }

    private var tile: some View {
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
        // TESTING.md §3 pins the label to the item label; position and state ride along
        // as the value, so VoiceOver still reads "Telephone, position 1, not placed yet".
        .accessibilityLabel(label)
        .accessibilityValue("position \(position + 1), \(stateDescription)")
        .accessibilityIdentifier("today.tile.\(position)")
        // Always available, `-uiTesting` or not: dragging is hard work with VoiceOver.
        .accessibilityAction(named: "Move up") { onMoveUp() }
        .accessibilityAction(named: "Move down") { onMoveDown() }
    }

    // `#if` sits at declaration level rather than inside the `HStack` builder, so the
    // result builder only ever sees plain Swift.
    #if DEBUG
    /// The deterministic reorder affordance for `KithUITests` and `KithLiveTests`.
    /// Never rendered outside `-uiTesting` / `-uiTestingControls`, and never on a
    /// locked tile (TESTING.md §1, §7).
    @ViewBuilder
    private var moveButtons: some View {
        if UITesting.controlsActive, !isLocked {
            moveButton(systemImage: "chevron.up", suffix: "up",
                       label: "Move tile \(position + 1) up", action: onMoveUp)
            moveButton(systemImage: "chevron.down", suffix: "down",
                       label: "Move tile \(position + 1) down", action: onMoveDown)
        }
    }

    private func moveButton(systemImage: String, suffix: String,
                            label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("today.tile.\(position).\(suffix)")
    }
    #else
    private var moveButtons: some View { EmptyView() }
    #endif
}
