// HubView.swift — the Today tab is now the games hub (docs/07 §"Product rules",
// PLAN-games.md "Screens"). Four rows: Lineup, Stars, Duo, Trail. Tapping one pushes
// its play screen onto this stack.

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
                    headerCard
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section("Today's games") {
                    ForEach(HubGame.allCases, id: \.self) { game in
                        row(for: game)
                    }
                }

                if model.resultPendingSync || model.gamePendingSync {
                    Section {
                        Label("Offline. Your scores will sync.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
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

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppModel.headerDate(model.today))
                .font(.headline)

            HStack(spacing: 16) {
                Label("\(model.streak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.kithAccent)
                    .accessibilityLabel("\(model.streak) day streak")
                    .accessibilityIdentifier("hub.streak")

                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text("Next games in \(model.countdownText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("hub.countdown")
                }

                Spacer(minLength: 0)
            }
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
                Image(systemName: game.symbolName)
                    .font(.title3)
                    .foregroundStyle(Color.kithAccent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .font(.body.weight(.medium))
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            // 44 pt minimum, and the row keeps that height at every Dynamic Type size.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.title), \(status)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("hub.row.\(game.slug)")
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
