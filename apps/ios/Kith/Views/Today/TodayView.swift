// TodayView.swift — docs/03 §2.

import KithCore
import LineupEngine
import Foundation
import SwiftUI
import UIKit

@MainActor
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var nearPositions: Set<Int> = []
    @State private var isFinishing = false
    /// Grows with Dynamic Type so the five rows always fit.
    @ScaledMetric private var tileListHeight: CGFloat = 330

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if model.resultPendingSync {
                        banner("Offline. Your score will sync.")
                    }

                    if let engine = model.engine, engine.phase == .playing {
                        puzzle(engine: engine)
                    } else if model.playedToday {
                        playedState
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.loadToday()
                await model.refreshBoard(kind: .friends, scopeId: nil, period: .today, force: true)
            }
        }
        // Registration and the contacts pre-prompt both land here with nothing loaded;
        // `bootstrap` only runs for an already-registered launch.
        .task { await loadIfNeeded() }
        .fullScreenCover(isPresented: $model.showResults) {
            ResultsView()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppModel.headerDate(model.today))
                    .font(.title3.weight(.semibold))
                if let number = model.puzzle?.number {
                    Text("#\(number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if model.streak > 0 {
                Text("🔥 \(model.streak)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.kithAccent.opacity(0.15)))
                    .accessibilityLabel("\(model.streak) day streak")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Playing

    @ViewBuilder
    private func puzzle(engine: LineupEngine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(engine.puzzle.prompt)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(engine.puzzle.direction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .kithCard()

        TileList(
            engine: engine,
            nearPositions: nearPositions,
            onMove: { source, destination in
                model.moveRows(from: source, to: destination)
            }
        )
        // The List needs a height because it sits inside a ScrollView; the rows
        // themselves are never height-constrained.
        .frame(height: tileListHeight)

        HStack {
            triesDots(used: engine.attempts.count)
            Spacer()
            timerLabel
        }

        Button("Lock in") {
            Task { await lockIn() }
        }
        .buttonStyle(PrimaryButtonStyle(enabled: engine.canSubmit && !isFinishing))
        .disabled(!engine.canSubmit || isFinishing)
        .accessibilityLabel("Lock in this order")
    }

    private func triesDots(used: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<LineupEngine.maxTries, id: \.self) { index in
                SwiftUI.Circle()
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                    .background(SwiftUI.Circle().fill(index < used ? Color.kithAccent : Color.clear))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(LineupEngine.maxTries - used) of \(LineupEngine.maxTries) tries left")
    }

    private var timerLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(AppModel.clock(model.elapsedMs))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Elapsed time \(AppModel.clock(model.elapsedMs))")
        }
    }

    /// A method rather than a body inside `.task`: that closure is `@Sendable` and does
    /// not inherit this view's `@MainActor` isolation, so the hop is the `await` on this.
    private func loadIfNeeded() async {
        if model.puzzle == nil {
            await model.loadToday()
        }
    }

    private func lockIn() async {
        isFinishing = true
        defer { isFinishing = false }

        guard let attempt = await model.lockIn() else { return }

        nearPositions = Set(attempt.feedback.indices.filter { attempt.feedback[$0] == .near })
        if attempt.isSolved {
            Haptics.solved()
        } else if model.engine?.phase == .failed {
            Haptics.failed()
        } else {
            Haptics.partial()
        }

        // Let the full green row land before the results screen (docs/03 §2).
        try? await Task.sleep(nanoseconds: 400_000_000)
        nearPositions = []
        if model.localResult != nil {
            model.showResults = true
        }
    }

    // MARK: Already played

    private var playedState: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let summary = model.resultsSummary {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summary.headline)
                        .font(.title2.weight(.semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(summary.score)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(summary.timeText)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    AttemptGrid(grid: summary.grid, square: 20)
                }
                .kithCard()
                .accessibilityElement(children: .contain)
            } else {
                Text("You've played today.")
                    .font(.title3.weight(.semibold))
                    .kithCard()
            }

            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text("Next puzzle in \(model.countdownText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let friendRows = Array(model.rows(kind: .friends, scopeId: nil, period: .today).prefix(3))
            if !friendRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(friendRows) { row in
                        HStack(spacing: 12) {
                            Text(row.rank.map { "\($0)" } ?? "–")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .leading)
                            AvatarView(name: row.name, size: 28, highlighted: row.isMe)
                            Text(row.name).font(.body)
                            Spacer()
                            Text(row.played ? "\(row.score)" : "—")
                                .font(.subheadline.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .kithCard()
            }

            Button("See the board") { model.tab = .board }
                .font(.subheadline.weight(.medium))
                .accessibilityLabel("See the board")

            if model.localResult != nil {
                Button("Show my result") { model.showResults = true }
                    .font(.subheadline)
                    .accessibilityLabel("Show my result again")
            }
        }
    }

    // MARK: No puzzle

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No puzzle loaded")
                .font(.title3.weight(.semibold))
            Text("Check your connection and pull down to try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") {
                Task { await model.loadToday() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Retry loading today's puzzle")
        }
        .kithCard()
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
