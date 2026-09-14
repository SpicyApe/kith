// GameResultsView.swift — the grid games' results screen, v2 (docs/08-visual-design.md
// §"Results (grid games) — v2"): a celebration card rather than a settings form — a hero
// band, the finished board rendered read-only, three stat tiles, the rank teaser, then
// Share and Done.

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
    /// Drives the one-shot solve haptic; `didFireSuccess` keeps it from re-firing if this
    /// view's `onAppear` runs again (e.g. a scene-phase hiccup) during the same presentation.
    @State private var successTrigger = false
    @State private var didFireSuccess = false

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

    /// Quint's answer, for the reveal shown on a fail or give-up (finding B3). Only
    /// available while this kind's session is still around (the live engine, not the
    /// server-side result), matching `shareRows` above.
    private var answer: String? {
        guard case .quint(let engine)? = model.activeGames[.quint]?.engine else { return nil }
        return engine.spec.answer
    }

    /// The game's SF Symbol for the hero band's icon circle. A purely visual choice, kept
    /// in step with `HubView.hubIconSymbol(for:)` rather than the frozen `GridGames`
    /// contract's own `GameKind.symbolName`.
    private var heroSymbol: String {
        switch kind {
        case .stars: return "star.fill"
        case .duo: return "circle.grid.2x2.fill"
        case .trail: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .quint: return "square.grid.3x3.fill"
        }
    }

    /// "Stars #12 · 8×8 · Sunday" — the puzzle number always resolves (from the live session
    /// or today's `dailyGames` row); the size only while the session is still around. Quint
    /// shows its guess progress instead of a size (docs/07 §Quint), e.g. "Quint #12 · 4/6".
    /// The weekday comes from the stored result's own date, not "today", so a result seen
    /// after midnight still reads correctly.
    private func subtitle(_ result: StoredGameResult) -> String {
        let number = model.activeGames[kind]?.number ?? model.dailyRow(for: kind)?.number ?? 0
        let weekday = LocalDay.weekdayName(result.date)
        var text: String
        if kind == .quint {
            text = "\(kind.title) #\(number) · \(AppModel.quintProgress(result))"
        } else if let size = model.activeGames[kind]?.engine.size {
            text = "\(kind.title) #\(number) · \(size)×\(size)"
        } else {
            text = "\(kind.title) #\(number)"
        }
        if !weekday.isEmpty { text += " · \(weekday)" }
        return text
    }

    var body: some View {
        ScrollView {
            if let result {
                VStack(alignment: .leading, spacing: 20) {
                    heroBand(result)
                    boardPreview
                    statTiles(result)
                    rankTeaser
                    VStack(spacing: 12) {
                        shareButton(result)
                        doneButton
                    }
                    footer
                }
                .padding(20)
            } else {
                Text("No result yet.")
                    .font(.headline)
                    .padding(40)
            }
        }
        .background(Color(.systemBackground))
        .sensoryFeedback(.success, trigger: successTrigger)
        .onAppear {
            guard !didFireSuccess, let result, result.solved else { return }
            didFireSuccess = true
            successTrigger.toggle()
        }
    }

    /// Clears the `showGameResults` binding only. `GameHostView`'s `fullScreenCover` is
    /// driven by that same binding, so setting it false already dismisses this cover;
    /// also calling `dismiss()` here raced a second, from-inside dismissal against it
    /// (finding B5) — the host performs its own pop once it sees the binding flip.
    private func close() {
        model.showGameResults = false
    }

    // MARK: Hero band

    /// Full-width gradient card (game colour → the same colour darkened 18%), white text:
    /// the game's symbol in a white-20% circle, the 40 pt rounded-black headline, the
    /// subtitle, and — on a Quint fail/give-up — the revealed answer.
    private func heroBand(_ result: StoredGameResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // docs/08 puts the symbol circle to the left of the headline, not stacked
            // above it (finding C3).
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: heroSymbol)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.2), in: SwiftUI.Circle())

                Text(AppModel.gameHeadline(result))
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gameResults.headline")
            }

            Text(subtitle(result))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))

            // The word is otherwise never revealed on a fail or give-up (finding B3).
            if kind == .quint, !result.solved, let answer {
                Text("The word was \(answer.uppercased())")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .accessibilityIdentifier("gameResults.answer")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Theme.color(for: kind), Self.darkened(Theme.color(for: kind), by: 0.18)],
                startPoint: .top, endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        )
    }

    /// `color` darkened by `fraction` in HSB space, resolved per-trait so the gradient
    /// still adapts light/dark the way every other `Theme` colour does — `UIColor(color)`
    /// alone would freeze the dynamic provider at whatever trait it happens to resolve
    /// against first.
    private static func darkened(_ color: Color, by fraction: CGFloat) -> Color {
        let base = UIColor(color)
        let dynamic = UIColor { trait in
            let resolved = base.resolvedColor(with: trait)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard resolved.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return resolved }
            return UIColor(hue: h, saturation: s, brightness: max(0, b * (1 - fraction)), alpha: a)
        }
        return Color(uiColor: dynamic)
    }

    // MARK: Board preview

    /// The finished board at ~200 pt, drawn with the game's own grid view and hit-testing
    /// off — "the moment people screenshot" (docs/08). Falls back to the share-rows emoji
    /// preview when this kind's session is gone (results reopened after relaunch), since
    /// only the live engine can render the real grid.
    @ViewBuilder
    private var boardPreview: some View {
        if let engine = model.activeGames[kind]?.engine {
            liveBoard(engine)
        } else {
            sharePreview
        }
    }

    @ViewBuilder
    private func liveBoard(_ engine: GameEngine) -> some View {
        switch engine {
        case .stars(let starsEngine):
            StarsView(engine: starsEngine)
                .allowsHitTesting(false)
                .frame(maxWidth: 200, maxHeight: 200)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your finished \(kind.title) board")
        case .duo(let duoEngine):
            DuoView(engine: duoEngine)
                .allowsHitTesting(false)
                .frame(maxWidth: 200, maxHeight: 200)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your finished \(kind.title) board")
        case .trail(let trailEngine):
            TrailView(engine: trailEngine)
                .allowsHitTesting(false)
                .frame(maxWidth: 200, maxHeight: 200)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your finished \(kind.title) board")
        case .quint(let quintEngine):
            // Quint's tiles are drawn at a fixed 32 pt, not scaled to fit a 200 pt box
            // (finding C2) — capping its height the way the square boards are capped
            // squeezed/clipped the grid, since Quint's aspect ratio isn't 1:1 the same way.
            QuintView(engine: quintEngine, tileSize: 32, showsKeyboard: false)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your finished \(kind.title) board")
        }
    }

    /// The same rows the share text carries, so what you post is what you saw — the v1
    /// fallback, kept for the no-live-engine case.
    @ViewBuilder
    private var sharePreview: some View {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paperMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your grid, \(rows.count) rows")
        }
    }

    // MARK: Stat tiles

    /// Three `paperMuted` tiles — Time, Streak (🔥 `model.streak`, still carrying identifier
    /// `gameResults.score`), and Mistakes (Quint: Guesses, "k/6") — docs/08 §"Results (grid
    /// games) — v2".
    private func statTiles(_ result: StoredGameResult) -> some View {
        HStack(spacing: 12) {
            statTile(AppModel.clock(result.elapsedMs), label: "Time")
                .accessibilityLabel("Time \(AppModel.clock(result.elapsedMs))")
                .accessibilityIdentifier("gameResults.time")

            statTile("🔥 \(model.streak)", label: "Streak")
                .accessibilityLabel("\(model.streak) day streak")
                .accessibilityIdentifier("gameResults.score")

            if kind == .quint {
                statTile(AppModel.quintProgress(result), label: "Guesses")
                    .accessibilityLabel("Guesses \(AppModel.quintProgress(result))")
            } else {
                statTile("\(result.mistakes)", label: "Mistakes")
                    .accessibilityLabel("Mistakes \(result.mistakes)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statTile(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label.uppercased())
                .font(.caption)
                .tracking(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.paperMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
    }

    // MARK: Rank teaser

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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(teaser). Open the board.")
            .accessibilityIdentifier("gameResults.rankTeaser")
        }
    }

    // MARK: Buttons

    /// Full-width filled Share in the game colour.
    private func shareButton(_ result: StoredGameResult) -> some View {
        let text = model.gameShareText(result, rows: shareRows)

        return ShareLink(item: text) {
            Label(didShare ? "Shared ✓" : "Share", systemImage: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(Color.white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.color(for: kind))
                )
        }
        .simultaneousGesture(TapGesture().onEnded {
            didShare = true
            model.markGameShared(kind)
        })
        .accessibilityLabel("Share your \(kind.title) result")
        .accessibilityIdentifier("gameResults.share")
    }

    /// Bordered Done, closing this cover (finding B5's close() above).
    private var doneButton: some View {
        Button("Done") { close() }
            .buttonStyle(SecondaryButtonStyle())
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
