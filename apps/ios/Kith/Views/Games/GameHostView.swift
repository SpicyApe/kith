// GameHostView.swift — shared chrome for Stars, Duo, Trail and Quint (PLAN-games.md
// "Screens", docs/08-visual-design.md §"Game host chrome").
//
// The navigation bar carries the game name and the running timer, plus a help button that
// presents a short rules sheet. Below the board, Reset / Give up sit in a bordered row.
// There is no Done button: Stars, Duo and Trail auto-submit the moment their engine reports
// the grid complete (docs/08-visual-design.md §"Auto-complete"); Quint already submits on
// its solving guess. Submission and all state live in `AppModel`.

import Foundation
import GridGames
import KithCore
import SwiftUI

@MainActor
struct GameHostView: View {
    let kind: GameKind

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showGiveUpConfirm = false
    @State private var showRules = false
    /// Set once the results cover has been shown, so dismissing it pops back to the hub
    /// rather than leaving a finished grid on screen.
    @State private var sawResults = false
    /// Guards the auto-complete `finishGame()` call (docs/08-visual-design.md
    /// §"Auto-complete") against firing twice for the same game — `onChange` fires again on
    /// every further engine mutation once `isComplete` is already true (Stars/Duo can still
    /// take paint moves after completion), so a simple "did we already start it" flag, keyed
    /// to this screen's own `kind`, is enough; a fresh `GameHostView` gets a fresh flag.
    @State private var autoFinishStarted = false

    /// Reads `activeGames[kind]` directly rather than `model.activeGame`, so this screen
    /// always shows its own kind's session even if another grid game is also in progress
    /// (finding A1).
    private var game: ActiveGame? {
        model.activeGames[kind]
    }

    /// A result stored before this screen was opened — the game was already played today.
    private var playedEarlier: StoredGameResult? {
        guard game == nil else { return nil }
        return model.result(for: kind)
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 16) {
            // Quint's board plus its three-row keyboard can run taller than an SE screen;
            // a ScrollView keeps every key hittable rather than letting the keyboard get
            // clipped or squeezed (finding C10). The other three games' square boards
            // already fit, so they stay unwrapped.
            if kind == .quint {
                ScrollView {
                    content
                }
            } else {
                content
            }
        }
        .padding(.horizontal, hostHorizontalPadding)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A plain `.navigationTitle` is hidden the moment a `.principal` toolbar item
            // is also present, so the title rides along inside that item instead (C1).
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(kind.title)
                        .font(.headline)
                    timer
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRules = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("\(kind.title) rules")
                .accessibilityIdentifier("game.help")
            }
        }
        // A method rather than a body inside `.task`: that closure is `@Sendable` and does
        // not inherit this view's `@MainActor` isolation, so the hop is the `await` on this.
        .task { await start() }
        // Auto-complete (docs/08-visual-design.md §"Auto-complete"): Stars, Duo and Trail
        // finish the moment their engine reports `isComplete`, no Done tap needed. Quint is
        // excluded — it already calls `finishGame()` itself the instant the solving guess is
        // accepted (`AppModel.quintSubmit()`), with no delay, so gating on `kind` here rather
        // than re-deriving "is this Quint" from the engine keeps the two paths from racing.
        .onChange(of: game?.engine.isComplete) { _, complete in
            guard kind != .quint else { return }
            guard complete == true else {
                // A Reset during the 0.6 s auto-finish window (below) flips `isComplete`
                // back to false before `finishGame()` runs — clear the latch so a fresh
                // completion of the *new* grid can still auto-finish (finding C4). Reset
                // is itself disabled while a finish is pending (`resetButton` below), but
                // this also covers `isComplete` going false for any other reason.
                autoFinishStarted = false
                return
            }
            guard !autoFinishStarted else { return }
            autoFinishStarted = true
            Task {
                if !reduceMotion {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
                await model.finishGame()
            }
        }
        .sheet(isPresented: $showRules) {
            GameRulesSheet(kind: kind)
        }
        .confirmationDialog(
            "Give up on \(kind.title)?",
            isPresented: $showGiveUpConfirm,
            titleVisibility: .visible
        ) {
            Button("Give up", role: .destructive) {
                Task { await model.giveUpGame() }
            }
            .accessibilityIdentifier("game.giveUp.confirm")
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("The day still counts as played, but the score is 100.")
        }
        .fullScreenCover(isPresented: $model.showGameResults) {
            GameResultsView(kind: kind)
        }
        .onChange(of: model.showGameResults) { _, shown in
            if shown {
                sawResults = true
            } else if sawResults {
                // `GameResultsView.close()` only clears the binding now (finding B5); the
                // pop back to the hub happens here, once, after that dismissal has already
                // started, rather than racing a second `dismiss()` against it.
                model.activeGames[kind] = nil
                Task { @MainActor in dismiss() }
            }
        }
    }

    /// Trail can go up to 9×9 (`GridMetrics` tightens cell spacing at that size); the 16 pt
    /// side padding used everywhere else would then push cells below a comfortable tap
    /// target, so the host itself narrows to 8 pt (finding C6).
    private var hostHorizontalPadding: CGFloat {
        (game?.engine.size ?? 0) >= 9 ? 8 : 16
    }

    private func start() async {
        await model.startGame(kind)
    }

    // MARK: Body states

    @ViewBuilder
    private var content: some View {
        if let stored = playedEarlier {
            playedCard(stored)
        } else if let game {
            grid(for: game)
            controls(for: game)
        } else if !model.isAvailable(kind) && !model.isBusy {
            unavailable
        } else if let error = model.activeGameErrors[kind] {
            startFailed(error)
        } else {
            ProgressView()
                .controlSize(.large)
                .padding(.top, 60)
                .accessibilityLabel("Loading \(kind.title)")
        }
    }

    /// A failed `startGame` used to leave this screen on the `ProgressView` above forever
    /// (finding B1); this renders the error instead, with a way back in.
    private func startFailed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                Task { await model.startGame(kind) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("game.retry")
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private func grid(for game: ActiveGame) -> some View {
        switch game.engine {
        case .stars(let engine):
            StarsView(engine: engine)
        case .duo(let engine):
            DuoView(engine: engine)
        case .trail(let engine):
            TrailView(engine: engine)
        case .quint(let engine):
            QuintView(engine: engine)
        }
    }

    /// Below the board: the mistake count (if any), then the Reset / Give up row
    /// (docs/08-visual-design.md §"Game host chrome").
    private func controls(for game: ActiveGame) -> some View {
        VStack(spacing: 10) {
            if game.mistakes > 0 {
                Text(game.mistakes == 1 ? "1 mistake" : "\(game.mistakes) mistakes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                // Quint has no Reset: a guess cannot be taken back once submitted
                // (docs/08-visual-design.md §"Quint").
                if game.kind != .quint {
                    resetButton
                }
                giveUpButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playedCard(_ stored: StoredGameResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppModel.gameHeadline(stored))
                .font(.title2.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("\(stored.score)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text(AppModel.clock(stored.elapsedMs))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text("Next games in \(model.countdownText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Show my result") {
                model.showGameResults = true
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("game.showResult")
        }
        .kithCard()
        .accessibilityElement(children: .contain)
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("\(kind.title) isn't available today.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 60)
    }

    // MARK: Toolbar

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(AppModel.clock(elapsedMs))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.paperMuted, in: Capsule())
                .accessibilityLabel("Elapsed time \(AppModel.clock(elapsedMs))")
                .accessibilityIdentifier("game.timer")
        }
    }

    private var elapsedMs: Int {
        if let finished = game?.finished { return finished.elapsedMs }
        if let stored = playedEarlier { return stored.elapsedMs }
        return game?.elapsedMs ?? 0
    }

    // MARK: Bottom row

    private var resetButton: some View {
        Button {
            model.resetGame()
        } label: {
            Text("Reset")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.paperMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        // Also disabled while an auto-finish is pending (finding C4): resetting mid-window
        // would otherwise race `finishGame()`, which is about to read the now-reset grid.
        .disabled(game == nil || game?.finished != nil || autoFinishStarted)
        .accessibilityLabel("Reset the grid")
        .accessibilityIdentifier("game.reset")
    }

    private var giveUpButton: some View {
        Button(role: .destructive) {
            showGiveUpConfirm = true
        } label: {
            Text("Give up")
                .font(.headline)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.danger.opacity(0.4), lineWidth: 1)
                )
        }
        .disabled(game == nil || game?.finished != nil)
        // Deliberately not just "Give up": the confirmation dialog's own destructive button
        // is titled "Give up", and two buttons with the same label make a UI test ambiguous.
        .accessibilityLabel("Give up on this game")
        .accessibilityIdentifier("game.giveUp")
    }

}

/// `game.help`'s sheet: three rule bullets per game (docs/07-games-hub.md) and a small
/// static 3×3 example rendered with the same cell styles the real grids use.
@MainActor
private struct GameRulesSheet: View {
    let kind: GameKind

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.bullets(for: kind), id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 10) {
                                SwiftUI.Circle()
                                    .fill(Theme.color(for: kind))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)
                                Text(bullet)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    example
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationTitle("\(kind.title) rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var example: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height, 160)
            RulesExampleGrid(kind: kind, side: side)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    static func bullets(for kind: GameKind) -> [String] {
        switch kind {
        case .stars:
            return [
                "Place exactly one star in every row, column and colour region.",
                "No two stars may touch, including diagonally.",
                "Tap a cell to cycle empty → ✕ → ★; drag to mark several cells ✕ at once.",
            ]
        case .duo:
            return [
                "Fill every row and column with three ● and three ◆ — never three of the same symbol in a row.",
                "A badge on the shared edge of two cells means = (same) or × (different).",
                "Tap a cell to cycle empty → ● → ◆.",
            ]
        case .trail:
            return [
                "Draw one path through every cell of the grid without crossing itself.",
                "Visit the numbered waypoints in order, starting at 1.",
                "Drag from the end of the path into an adjacent cell; drag back to retract.",
            ]
        case .quint:
            return [
                "Guess the five-letter word in six tries. Every guess must be a real word.",
                "Each guess turns green for the right letter in the right place, yellow for the " +
                "right letter in the wrong place, and gray for a letter that isn't in the word.",
                "The keyboard shows each letter's best result so far. No hard mode.",
            ]
        }
    }
}

/// A fixed, non-interactive 3×3 illustration using the same fills, lines and marks as the
/// real grid views, purely for the rules sheet.
@MainActor
private struct RulesExampleGrid: View {
    let kind: GameKind
    let side: CGFloat

    private static let starsRegions = [[0, 0, 1], [0, 1, 1], [2, 2, 1]]

    var body: some View {
        let metrics = GridMetrics(size: 3, spacing: 0, side: side)
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { column in
                            cell(row: row, column: column, metrics: metrics)
                        }
                    }
                }
            }
            metrics.lineOverlay(regions: kind == .stars ? Self.starsRegions : nil)
        }
        .gridBoardChrome()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(row: Int, column: Int, metrics: GridMetrics) -> some View {
        switch kind {
        case .stars:
            ZStack {
                Theme.region(Self.starsRegions[row][column])
                if row == 0, column == 2 {
                    Image(systemName: "star.fill")
                        .font(.system(size: max(9, metrics.cell * 0.56)))
                        .foregroundStyle(Theme.ink)
                } else if row == 1, column == 0 {
                    Image(systemName: "xmark")
                        .font(.system(size: max(8, metrics.cell * 0.34), weight: .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.4))
                }
            }
            .frame(width: metrics.cell, height: metrics.cell)
            .clipped()
        case .duo:
            ZStack {
                Theme.paper
                if row == 0, column == 0 {
                    Image(systemName: "circle.fill")
                        .font(.system(size: max(9, metrics.cell * 0.52)))
                        .foregroundStyle(Theme.duo)
                } else if row == 0, column == 2 {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: max(9, metrics.cell * 0.52)))
                        .foregroundStyle(Theme.duoAlt)
                }
            }
            .frame(width: metrics.cell, height: metrics.cell)
            .clipped()
        case .trail:
            ZStack {
                Theme.paper
                if row == 0, column == 0 {
                    waypoint("1", metrics: metrics)
                } else if row == 2, column == 2 {
                    waypoint("2", metrics: metrics)
                }
            }
            .frame(width: metrics.cell, height: metrics.cell)
            .clipped()
        case .quint:
            ZStack {
                Theme.paper
                if row == 0, column == 0 {
                    quintTile("C", fill: Theme.trail, text: Color.white, metrics: metrics)
                } else if row == 0, column == 1 {
                    quintTile("R", fill: Theme.duo, text: Color.white, metrics: metrics)
                } else if row == 0, column == 2 {
                    quintTile("X", fill: Theme.paperMuted, text: Theme.ink, metrics: metrics)
                }
            }
            .frame(width: metrics.cell, height: metrics.cell)
            .clipped()
        }
    }

    private func quintTile(_ letter: String, fill: Color, text: Color, metrics: GridMetrics) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .overlay(
                Text(letter)
                    .font(.system(size: max(9, metrics.cell * 0.4), weight: .black, design: .rounded))
                    .foregroundStyle(text)
            )
            .frame(width: metrics.cell * 0.78, height: metrics.cell * 0.78)
    }

    /// Same disc style as the real Trail grid (docs/08-visual-design.md §"Trail discs
    /// (contrast fix)"): `paper` fill, 2.5 pt `ink` ring, `ink` numeral at 46% of the cell.
    private func waypoint(_ text: String, metrics: GridMetrics) -> some View {
        Text(text)
            .font(.system(size: max(10, metrics.cell * 0.46), weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .frame(width: metrics.cell * 0.66, height: metrics.cell * 0.66)
            .background(
                SwiftUI.Circle()
                    .fill(Theme.paper)
                    .overlay(SwiftUI.Circle().strokeBorder(Theme.ink, lineWidth: 2.5))
            )
    }
}
