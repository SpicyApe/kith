// HubView.swift — the Today tab is now the games hub (docs/07 §"Product rules",
// docs/08 §"Hub (Today tab)"). A pill row (streak + countdown), then one card per game in
// a plain list section. Tapping a row pushes its play screen onto this stack.

import Foundation
import GridGames
import KithCore
import SwiftUI

/// What a hub row pushes. `Hashable` so it can be a `NavigationLink` value.
enum HubDestination: Hashable {
    case lineup
    case game(GameKind)
}

@MainActor
struct HubView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    pillRow
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(HubGame.allCases, id: \.self) { game in
                        row(for: game)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                if model.resultPendingSync || model.gamePendingSync {
                    Section {
                        Label("Offline. Your scores will sync.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: HubDestination.self) { destination in
                switch destination {
                case .lineup:
                    TodayView()
                case .game(let kind):
                    GameHostView(kind: kind)
                }
            }
            .refreshable { await reload() }
        }
        // Registration and the contacts pre-prompt both land here with nothing loaded;
        // `bootstrap` only runs for an already-registered launch.
        .task { await loadIfNeeded() }
    }

    // MARK: Pill row

    private var pillRow: some View {
        HStack(spacing: 10) {
            Label("\(model.streak)", systemImage: "flame.fill")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.paperMuted, in: Capsule())
                .accessibilityLabel("\(model.streak) day streak")
                .accessibilityIdentifier("hub.streak")

            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text("New games in \(model.countdownText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.paperMuted, in: Capsule())
                    .accessibilityIdentifier("hub.countdown")
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(for game: HubGame) -> some View {
        let enabled = model.isHubRowEnabled(game)
        let status = model.hubStatus(for: game)

        NavigationLink(value: destination(for: game)) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: Theme.cardRadius - 4, style: .continuous)
                    .fill(Theme.color(for: game))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: hubIconSymbol(for: game))
                            .font(.title2)
                            .foregroundStyle(Color.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .font(.title3.bold())
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                trailing(for: game)
            }
            // 44 pt minimum, and the row keeps that height at every Dynamic Type size.
            .frame(minHeight: 56)
            .padding(12)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.title), \(status)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("hub.row.\(game.slug)")
    }

    /// The right-hand indicator: a time/score badge once played, "Gave up" in secondary
    /// text, or a filled "Play" capsule in the game's colour while it is still open.
    @ViewBuilder
    private func trailing(for game: HubGame) -> some View {
        switch game {
        case .lineup:
            if let row = model.myResults.first(where: { $0.puzzle_date == model.today }) {
                if row.solved {
                    badge("\(row.score)")
                } else {
                    Text("Out of tries")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                playCapsule(for: game)
            }
        case .grid(let kind):
            if let stored = model.result(for: kind) {
                if stored.gaveUp {
                    Text("Gave up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    badge(AppModel.clock(stored.elapsedMs))
                }
            } else if model.isAvailable(kind) {
                playCapsule(for: game)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.paperMuted, in: Capsule())
    }

    private func playCapsule(for game: HubGame) -> some View {
        Text("Play")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Theme.color(for: game), in: Capsule())
    }

    /// docs/08's hub icons are a purely visual choice independent of `GameKind.symbolName`
    /// (a frozen `GridGames` contract used elsewhere for its own purposes), so the mapping
    /// lives here rather than on the enum.
    private func hubIconSymbol(for game: HubGame) -> String {
        switch game {
        case .lineup: return "square.stack.3d.up"
        case .grid(.stars): return "star.fill"
        case .grid(.duo): return "circle.grid.2x2.fill"
        case .grid(.trail): return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .grid(.quint): return "square.grid.3x3.fill"
        }
    }

    private func destination(for game: HubGame) -> HubDestination {
        switch game {
        case .lineup: return .lineup
        case .grid(let kind): return .game(kind)
        }
    }

    // MARK: Loading

    /// A method rather than a body inside `.task`: that closure is `@Sendable` and does not
    /// inherit this view's `@MainActor` isolation, so the hop is the `await` on this.
    private func loadIfNeeded() async {
        if model.puzzle == nil || model.dailyGames.isEmpty {
            await model.loadToday()
        }
    }

    private func reload() async {
        await model.loadToday()
        await model.refreshBoard(kind: .friends, scopeId: nil, period: .today, force: true)
    }
}
