// QuintView.swift — Wordle-style board (docs/07 §"Quint", docs/08 §"Quint").
//
// Unlike Stars/Duo/Trail this board is not square (6 rows × 5 columns), so it does not
// reuse `GridMetrics`'s square-fit layout or `gridBoardChrome()`: tiles are simply laid out
// in a `VStack`/`HStack` of flexible-width, individually-square cells, which lets the board
// size itself without `GameHostView` ever needing to force an `aspectRatio(1)` on it. Below
// the board sits a three-row on-screen keyboard.

import Foundation
import GridGames
import SwiftUI

@MainActor
struct QuintView: View {
    let engine: QuintEngine
    /// Edge length of one tile. Defaults to the normal in-game size; `GameResultsView`
    /// passes 32 to fit the results card's ~200 pt board preview (docs/08-visual-design.md
    /// §"Results (grid games) — v2").
    var tileSize: CGFloat = 62
    /// Whether to render the reveal caption and the on-screen keyboard below the grid.
    /// `GameResultsView` passes `false` — its board preview shows only the finished tiles,
    /// read-only, with no keyboard beneath them.
    var showsKeyboard: Bool = true

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-tile flip angle, keyed by row/column. 90° is edge-on (hidden), 0° is flat
    /// (revealed). Only ever populated for rows that have just been submitted.
    @State private var revealAngles: [GridPoint: Double] = [:]
    @State private var shakeOffset: CGFloat = 0
    /// Under Reduce Motion the shake itself is skipped, so a not-a-word guess instead
    /// flashes the current row's borders red for a beat (finding B5).
    @State private var borderFlash = false

    private var shakeCounter: Int { model.activeGames[.quint]?.quintShake ?? 0 }
    private var currentRow: Int { engine.guesses.count }

    init(engine: QuintEngine, tileSize: CGFloat = 62, showsKeyboard: Bool = true) {
        self.engine = engine
        self.tileSize = tileSize
        self.showsKeyboard = showsKeyboard
    }

    var body: some View {
        VStack(spacing: 20) {
            board
            if showsKeyboard {
                revealCaption
                keyboard
                Spacer(minLength: 0)
            }
        }
        .onChange(of: engine.guesses.count) { old, new in
            guard new > old else { return }
            revealRow(new - 1)
        }
        .onChange(of: shakeCounter) { _, _ in
            triggerShake()
        }
        .sensoryFeedback(.selection, trigger: model.activeGames[.quint]?.moves ?? 0)
        .sensoryFeedback(.warning, trigger: shakeCounter)
        .sensoryFeedback(.success, trigger: engine.isSolved)
        .accessibilityElement(children: .contain)
    }

    // MARK: Board

    private var board: some View {
        VStack(spacing: 6) {
            ForEach(0..<engine.spec.guesses, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<engine.spec.n, id: \.self) { column in
                        tile(row: row, column: column)
                    }
                }
                .offset(x: row == currentRow ? shakeOffset : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quint grid, \(engine.spec.guesses) guesses of \(engine.spec.n) letters")
    }

    /// The word is otherwise never shown on a fail or give-up (finding B3) — the board only
    /// ever renders marks for guesses actually made.
    @ViewBuilder
    private var revealCaption: some View {
        if engine.isComplete, !engine.isSolved {
            Text("The word was \(engine.spec.answer.uppercased())")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("quint.reveal")
        }
    }

    private func tile(row: Int, column: Int) -> some View {
        let letter = self.letter(row: row, column: column)
        let mark = self.mark(row: row, column: column)
        let hasLetter = letter != nil

        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill(for: mark))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor(row: row, hasLetter: hasLetter, mark: mark),
                                  lineWidth: mark == nil && hasLetter ? 2.5 : 2)
            )
            .overlay(
                Text(letter.map { String($0).uppercased() } ?? "")
                    .font(.system(size: max(9, tileSize * 0.42), weight: .black, design: .rounded))
                    .foregroundStyle(textColor(for: mark))
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: tileSize, maxHeight: tileSize)
            .rotation3DEffect(.degrees(angle(row: row, column: column)),
                              axis: (x: 1, y: 0, z: 0))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(row: row, column: column, letter: letter, mark: mark))
            .accessibilityIdentifier("quint.tile.\(row).\(column)")
    }

    private func letter(row: Int, column: Int) -> Character? {
        if row < engine.guesses.count {
            let letters = Array(engine.guesses[row])
            return column < letters.count ? letters[column] : nil
        }
        if row == engine.guesses.count {
            let letters = Array(engine.current)
            return column < letters.count ? letters[column] : nil
        }
        return nil
    }

    private func mark(row: Int, column: Int) -> QuintMark? {
        engine.marks(for: row)?[column]
    }

    private func fill(for mark: QuintMark?) -> Color {
        switch mark {
        case .hit: return Theme.trail
        case .near: return Theme.duo
        case .miss: return Theme.paperMuted
        case nil: return Theme.paper
        }
    }

    private func textColor(for mark: QuintMark?) -> Color {
        switch mark {
        case .hit, .near: return .white
        case .miss: return Theme.ink
        case nil: return Theme.ink
        }
    }

    private func borderColor(row: Int, hasLetter: Bool, mark: QuintMark?) -> Color {
        guard mark == nil else { return .clear }
        if borderFlash, row == currentRow { return Theme.danger }
        return hasLetter ? Theme.ink : Theme.ink.opacity(0.22)
    }

    private func angle(row: Int, column: Int) -> Double {
        revealAngles[GridPoint(row: row, col: column)] ?? 0
    }

    private static func spoken(_ mark: QuintMark) -> String {
        switch mark {
        case .hit: return "hit"
        case .near: return "near"
        case .miss: return "miss"
        }
    }

    /// "row 2 letter 3, C, hit" (docs/07/08; 1-based, matching `today.tile.<i>` and the
    /// other grids' spoken labels).
    private func accessibilityLabel(row: Int, column: Int, letter: Character?, mark: QuintMark?) -> String {
        let letterText = letter.map { String($0).uppercased() } ?? "empty"
        var parts = ["row \(row + 1) letter \(column + 1)", letterText]
        if let mark { parts.append(Self.spoken(mark)) }
        return parts.joined(separator: ", ")
    }

    // MARK: Reveal / shake animation

    /// Flips the just-submitted row's tiles from edge-on to flat, one at a time, unless
    /// Reduce Motion is on (docs/08: "skipped under Reduce Motion").
    private func revealRow(_ row: Int) {
        guard !reduceMotion else { return }
        for column in 0..<engine.spec.n {
            revealAngles[GridPoint(row: row, col: column)] = 90
        }
        // Setting 90 then immediately animating to 0 in the same tick never lets SwiftUI
        // render the edge-on state first, so the flip appeared to skip straight to flat.
        // Yielding once forces that intermediate render before the animated mutation runs.
        Task { @MainActor in
            await Task.yield()
            for column in 0..<engine.spec.n {
                withAnimation(.easeInOut(duration: 0.3).delay(Double(column) * 0.12)) {
                    revealAngles[GridPoint(row: row, col: column)] = 0
                }
            }
        }
    }

    /// A not-a-word guess shakes the current row (docs/07/08). Reduce Motion skips the
    /// shake, so it flashes the row's borders red instead — and either way an accessibility
    /// announcement carries the feedback for anyone not watching the row (finding B5).
    private func triggerShake() {
        guard shakeCounter > 0 else { return }
        AccessibilityNotification.Announcement("Not in the word list").post()
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.15)) { borderFlash = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                withAnimation(.easeInOut(duration: 0.15)) { borderFlash = false }
            }
            return
        }
        withAnimation(.linear(duration: 0.06)) { shakeOffset = -8 }
        withAnimation(.linear(duration: 0.06).delay(0.06)) { shakeOffset = 8 }
        withAnimation(.linear(duration: 0.06).delay(0.12)) { shakeOffset = -6 }
        withAnimation(.linear(duration: 0.06).delay(0.18)) { shakeOffset = 6 }
        withAnimation(.linear(duration: 0.06).delay(0.24)) { shakeOffset = 0 }
    }

    // MARK: Keyboard

    private static let row1 = Array("qwertyuiop")
    private static let row2 = Array("asdfghjkl")
    private static let row3 = Array("zxcvbnm")

    private var keyboard: some View {
        VStack(spacing: 8) {
            keyRow(Self.row1)
            keyRow(Self.row2)
            HStack(spacing: 6) {
                enterKey
                ForEach(Self.row3, id: \.self) { letter in keyButton(letter) }
                backspaceKey
            }
        }
        .accessibilityElement(children: .contain)
        // The ten-key top row already has no width to spare, so cap how far Dynamic Type
        // can grow it rather than letting keys overflow or shrink past a tappable size
        // (finding C18); `.body`-relative fonts on the keys still scale up to that cap.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func keyRow(_ letters: [Character]) -> some View {
        HStack(spacing: 6) {
            ForEach(letters, id: \.self) { letter in keyButton(letter) }
        }
    }

    private func keyButton(_ letter: Character) -> some View {
        let mark = engine.keyMarks[letter]
        return Button {
            model.quintType(letter)
        } label: {
            Text(String(letter).uppercased())
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(keyTextColor(for: mark))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(keyFill(for: mark), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .opacity(mark == .miss ? 0.35 : 1)
        .accessibilityLabel(String(letter).uppercased() + (mark.map { ", \(Self.spoken($0))" } ?? ""))
        .accessibilityIdentifier("quint.key.\(letter)")
    }

    private var enterKey: some View {
        Button {
            model.quintSubmit()
        } label: {
            Text("ENTER")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                // Fixed width on purpose: a flexible width plus `layoutPriority(1)` on the two
                // wide keys let them absorb the whole row and squeezed the seven letter keys
                // to zero width (CI: "quint.key.c" had a 0 × 46 frame).
                .frame(width: 54, height: 46)
                .background(Theme.paperMuted, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityLabel("Enter")
        .accessibilityIdentifier("quint.key.enter")
    }

    private var backspaceKey: some View {
        Button {
            model.quintBackspace()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 54, height: 46)
                .background(Theme.paperMuted, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityLabel("Backspace")
        .accessibilityIdentifier("quint.key.backspace")
    }

    private func keyFill(for mark: QuintMark?) -> Color {
        switch mark {
        case .hit: return Theme.trail
        case .near: return Theme.duo
        case .miss: return Theme.paperMuted
        case nil: return Theme.paperMuted
        }
    }

    private func keyTextColor(for mark: QuintMark?) -> Color {
        switch mark {
        case .hit, .near: return .white
        case .miss, nil: return Theme.ink
        }
    }
}
