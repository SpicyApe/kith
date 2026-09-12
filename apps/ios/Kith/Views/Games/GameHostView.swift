// GameHostView.swift — shared chrome for Stars, Duo and Trail (PLAN-games.md "Screens").
//
// The navigation bar carries the running timer; the trailing group carries Reset, a
// destructive "Give up" behind a confirmation dialog, and a "Done" that only appears once
// the engine reports the grid complete. Submission and all state live in `AppModel`.

import Foundation
import GridGames
import KithCore
import SwiftUI

@MainActor
struct GameHostView: View {
    let kind: GameKind

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showGiveUpConfirm = false
    /// Set once the results cover has been shown, so dismissing it pops back to the hub
    /// rather than leaving a finished grid on screen.
    @State private var sawResults = false

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
            content
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if game?.engine.isComplete == true, game?.finished == nil {
                    doneButton
                }
                resetButton
                giveUpButton
            }
        }
        // A method rather than a body inside `.task`: that closure is `@Sendable` and does
        // not inherit this view's `@MainActor` isolation, so the hop is the `await` on this.
        .task { await start() }
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
            footer(for: game)
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
        }
    }

    private func footer(for game: ActiveGame) -> some View {
        VStack(spacing: 6) {
            Text(Self.rules(for: kind))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if game.mistakes > 0 {
                Text(game.mistakes == 1 ? "1 mistake" : "\(game.mistakes) mistakes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
                .foregroundStyle(.secondary)
                .accessibilityLabel("Elapsed time \(AppModel.clock(elapsedMs))")
                .accessibilityIdentifier("game.timer")
        }
    }

    private var elapsedMs: Int {
        if let finished = game?.finished { return finished.elapsedMs }
        if let stored = playedEarlier { return stored.elapsedMs }
        return game?.elapsedMs ?? 0
    }

    private var doneButton: some View {
        Button {
            Task { await model.finishGame() }
        } label: {
            Label("Done", systemImage: "checkmark.circle.fill")
        }
        .disabled(game?.isFinishing == true)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Done, submit this grid")
        .accessibilityIdentifier("game.done")
    }

    private var resetButton: some View {
        Button {
            model.resetGame()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .disabled(game == nil || game?.finished != nil)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Reset the grid")
        .accessibilityIdentifier("game.reset")
    }

    private var giveUpButton: some View {
        Button(role: .destructive) {
            showGiveUpConfirm = true
        } label: {
            Label("Give up", systemImage: "flag.fill")
        }
        .disabled(game == nil || game?.finished != nil)
        .frame(minWidth: 44, minHeight: 44)
        // Deliberately not just "Give up": the confirmation dialog's own destructive button
        // is titled "Give up", and two buttons with the same label make a UI test ambiguous.
        .accessibilityLabel("Give up on this game")
        .accessibilityIdentifier("game.giveUp")
    }

    // MARK: Copy

    static func rules(for kind: GameKind) -> String {
        switch kind {
        case .stars:
            return "One star in every row, column and colour. No two stars may touch. Tap to cycle; drag to mark ✕."
        case .duo:
            return "Three of each symbol in every row and column, never three alike in a row. Tap to cycle."
        case .trail:
            return "Draw one path through every cell, visiting the numbers in order. Drag from the end of the path."
        }
    }
}
