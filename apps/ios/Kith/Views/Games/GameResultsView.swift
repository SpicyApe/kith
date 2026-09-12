// GameResultsView.swift — the grid games' results screen. Same shape as `ResultsView`:
// headline, time, score, a preview of the share rows, streak, rank teaser, share and copy.

import Foundation
import GridGames
import KithCore
import SwiftUI
import UIKit

@MainActor
struct GameResultsView: View {
    let kind: GameKind

    @Environment(AppModel.self) private var model

    @State private var didShare = false

    /// Reads `activeGames[kind]` rather than `model.activeGame`, matching `GameHostView`
    /// (finding A1) — this cover always shows `kind`'s own result even if another grid
    /// game also has a session open.
    private var result: StoredGameResult? {
        model.activeGames[kind]?.finished ?? model.result(for: kind)
    }

    private var shareRows: [String] {
        guard let active = model.activeGames[kind] else { return [] }
        return active.engine.shareRows()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let result {
                    VStack(alignment: .leading, spacing: 24) {
                        outcome(result)
                        gridPreview
                        streakLine
                        rankTeaser
                        shareButtons(result)
                        footer
                    }
                    .padding(20)
                } else {
                    Text("No result yet.")
                        .font(.headline)
                        .padding(40)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { close() }
                        .accessibilityLabel("Close results")
                }
            }
        }
    }

    /// Clears the `showGameResults` binding only. `GameHostView`'s `fullScreenCover` is
    /// driven by that same binding, so setting it false already dismisses this cover;
    /// also calling `dismiss()` here raced a second, from-inside dismissal against it
    /// (finding B5) — the host performs its own pop once it sees the binding flip.
    private func close() {
        model.showGameResults = false
    }

    // MARK: Sections

    private func outcome(_ result: StoredGameResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppModel.gameHeadline(result))
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gameResults.headline")

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("\(result.score)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .accessibilityLabel("Score \(result.score)")
                    .accessibilityIdentifier("gameResults.score")
                Text(AppModel.clock(result.elapsedMs))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("Time \(AppModel.clock(result.elapsedMs))")
                    .accessibilityIdentifier("gameResults.time")
            }

            if result.mistakes > 0 {
                Text(result.mistakes == 1 ? "1 mistake" : "\(result.mistakes) mistakes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// The same rows the share text carries, so what you post is what you saw.
    @ViewBuilder
    private var gridPreview: some View {
        let rows = shareRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(.footnote.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .kithCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your grid, \(rows.count) rows")
        }
    }

    @ViewBuilder
    private var streakLine: some View {
        if model.streak > 0 {
            Label("\(model.streak)-day streak", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(Color.kithAccent)
                .accessibilityLabel("\(model.streak) day streak")
        }
    }

    @ViewBuilder
    private var rankTeaser: some View {
        if let teaser = model.gameRankTeaser(for: kind) {
            Button {
                model.tab = .board
                close()
            } label: {
                HStack {
                    Text(teaser)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .kithCard()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(teaser). Open the board.")
            .accessibilityIdentifier("gameResults.rankTeaser")
        }
    }

    private func shareButtons(_ result: StoredGameResult) -> some View {
        let text = model.gameShareText(result, rows: shareRows)

        return VStack(spacing: 12) {
            ShareLink(item: text) {
                Text(didShare ? "Shared ✓" : "Share")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.kithAccent)
                    )
            }
            .simultaneousGesture(TapGesture().onEnded {
                didShare = true
                model.markGameShared(kind)
            })
            .accessibilityLabel("Share your \(kind.title) result")
            .accessibilityIdentifier("gameResults.share")

            Button("Copy") {
                UIPasteboard.general.string = text
                model.show(toast: "Copied.", isError: false)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Copy your result to the clipboard")
            .accessibilityIdentifier("gameResults.copy")
        }
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Text("Next games in \(model.countdownText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
