// BoardView.swift — docs/03 §4.

import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct BoardView: View {
    @Environment(AppModel.self) private var model

    @State private var kind: BoardKind = .friends
    @State private var period: BoardPeriod = .today
    @State private var reactingTo: String?

    private var scopeId: String? {
        kind == .circle ? model.selectedCircleId : nil
    }

    private var rows: [BoardDisplayRow] {
        model.rows(kind: kind, scopeId: scopeId, period: period)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Board", selection: $kind) {
                    Text("Friends").tag(BoardKind.friends)
                    Text("Circles").tag(BoardKind.circle)
                    Text("Everyone").tag(BoardKind.everyone)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Which board")
                .accessibilityIdentifier("board.kind")

                Picker("Period", selection: $period) {
                    Text("Today").tag(BoardPeriod.today)
                    Text("Week").tag(BoardPeriod.week)
                    Text("All-time").tag(BoardPeriod.all)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                // The Everyone board is today-only on the server; the control would
                // otherwise offer two periods that silently return the same rows.
                .disabled(kind == .everyone)
                .accessibilityLabel("Which period")
                .accessibilityIdentifier("board.period")

                if kind == .circle {
                    circleChips
                }

                header

                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: reloadKey) { await reload(force: false) }
            // Arriving at the board is what completes the "friends found" onboarding
            // step; FriendsFoundStep's button only switches tabs.
            .task { await completeFriendsFoundStep() }
            .onChange(of: kind) { _, k in
                if k == .everyone { period = .today }
            }
            .refreshable {
                await model.syncContacts(userInitiated: true)
                await reload(force: true)
            }
        }
    }

    private var reloadKey: String {
        "\(kind.rawValue)|\(scopeId ?? "")|\(period.rawValue)|\(model.today)"
    }

    private func reload(force: Bool) async {
        if kind == .circle, model.circles.isEmpty {
            await model.loadCircles()
        }
        await model.refreshBoard(kind: kind, scopeId: scopeId, period: period, force: force)
    }

    /// A method rather than a body inside `.task`, because `.task` takes a `@Sendable`
    /// closure that does not inherit this view's `@MainActor` isolation; awaiting a
    /// main-actor method is the hop.
    private func completeFriendsFoundStep() async {
        if model.tail == .friendsFound {
            model.advanceTail()
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch kind {
        case .friends:
            HStack {
                Text(model.boardHeader(kind: .friends, scopeId: nil, period: period))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("board.header")
                Spacer()
            }
        case .circle:
            if let circle = model.circles.first(where: { $0.id == model.selectedCircleId }) {
                HStack {
                    Text("KITH-\(circle.code)")
                        .font(.subheadline.monospaced())
                    Button {
                        UIPasteboard.general.string = "KITH-\(circle.code)"
                        model.show(toast: "Code copied.", isError: false)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy the circle code")
                    Spacer()
                }
            }
        case .everyone:
            HStack {
                Text("Everyone playing today")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var circleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.circles) { circle in
                    Button {
                        model.selectedCircleId = circle.id
                    } label: {
                        Text(circle.name)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    circle.id == model.selectedCircleId
                                        ? Color.kithAccent.opacity(0.2)
                                        : Color.secondary.opacity(0.12)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Circle \(circle.name)")
                }
                Button("+ New") { model.showCreateCircleSheet = true; model.tab = .circles }
                    .font(.subheadline)
                    .accessibilityLabel("Create a new circle")
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var content: some View {
        // `rows` recomputes the whole presenter pass on every read, so bind it once and
        // partition that single snapshot.
        let all = rows
        let played = all.filter(\.played)
        let unplayed = all.filter { !$0.played }

        if all.isEmpty {
            emptyState
        } else {
            List {
                ForEach(played) { row in
                    BoardRowView(row: row, period: period, showReactions: kind != .everyone) {
                        reactingTo = row.userId
                    }
                }
                if !unplayed.isEmpty {
                    Section("Haven't played yet") {
                        ForEach(unplayed) { row in
                            BoardRowView(row: row, period: period, showReactions: false, onReact: {})
                                .opacity(0.55)
                        }
                    }
                }
            }
            .listStyle(.plain)
            // docs/03 §4: your own row sticks to the bottom once the list is long
            // enough that it can scroll out of view.
            .safeAreaInset(edge: .bottom) {
                if all.count > 8, let me = all.first(where: \.isMe) {
                    BoardRowView(row: me, period: period, showReactions: false, onReact: {})
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                }
            }
            .confirmationDialog(
                "React",
                isPresented: Binding(
                    get: { reactingTo != nil },
                    set: { if !$0 { reactingTo = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(reactionEmoji, id: \.self) { emoji in
                    Button(emoji) {
                        if let target = reactingTo {
                            Task { await model.react(to: target, emoji: emoji) }
                        }
                        reactingTo = nil
                    }
                }
                Button("Cancel", role: .cancel) { reactingTo = nil }
            }
        }
    }

    /// Each board is empty for a different reason, and the circle board has its own
    /// join-code affordance in the header, so "Invite" would be the wrong button there.
    private var emptyHeadline: String {
        switch kind {
        case .friends:
            return "None of your contacts play yet. Be the one who started it."
        case .circle:
            return model.circles.isEmpty
                ? "You're not in a circle yet. Create one or join with a code."
                : "Nobody in this circle has played today."
        case .everyone:
            return "Nobody has played today yet. You could be first."
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text(emptyHeadline)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if kind != .circle {
                ShareLink(item: inviteText) {
                    Text("Invite")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.kithAccent))
                }
                .accessibilityLabel("Invite people to Kith")
                .accessibilityIdentifier("board.empty.invite")
            }

            Button("Create a circle") {
                model.showCreateCircleSheet = true
                model.tab = .circles
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Create a circle")
            .accessibilityIdentifier("board.empty.createCircle")

            if model.contactsState == .limited {
                HStack(spacing: 6) {
                    Text("Sharing \(model.sharedContactCount) contacts")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Add more") { openSettings() }
                        .font(.footnote)
                        .accessibilityLabel("Add more contacts in Settings")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var inviteText: String {
        InvitePresenter.text(
            webBase: AppConfig.webBase.absoluteString,
            code: model.profile?.invite_code ?? "",
            puzzleNumber: model.puzzle?.number
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - One row

@MainActor
struct BoardRowView: View {
    let row: BoardDisplayRow
    let period: BoardPeriod
    let showReactions: Bool
    let onReact: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(row.rank.map { "\($0)" } ?? "–")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            MovementChip(movement: row.movement)

            AvatarView(name: row.name, size: 32, highlighted: row.isMe)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.weight(row.isMe ? .semibold : .regular))
                    .lineLimit(1)
                if let taunt = row.taunt, !taunt.isEmpty {
                    Text(taunt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !row.reactions.isEmpty {
                    Text(row.reactions.joined())
                        .font(.caption)
                }
            }

            Spacer(minLength: 8)

            if period == .today, !row.miniGrid.isEmpty {
                MiniGrid(feedback: row.miniGrid)
            }

            Text(row.played ? "\(row.score)" : "—")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 44, alignment: .trailing)

            if showReactions, !row.isMe, row.played {
                Button {
                    onReact()
                } label: {
                    Image(systemName: row.myReaction == nil ? "face.smiling" : "face.smiling.inverse")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React to \(row.name)")
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            if row.isMe {
                Rectangle()
                    .fill(Color.kithAccent)
                    .frame(width: 3)
                    .offset(x: -12)
            }
        }
        // `.contain` rather than `.combine`: the row keeps its own summary label, and the
        // name inside it (notably "You") stays an addressable static text for UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("board.row.\(row.userId)")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let rank = row.rank { parts.append("rank \(rank)") }
        parts.append(row.name)
        parts.append(row.played ? "score \(row.score)" : "hasn't played yet")
        if let taunt = row.taunt, !taunt.isEmpty { parts.append("says \(taunt)") }
        return parts.joined(separator: ", ")
    }
}
