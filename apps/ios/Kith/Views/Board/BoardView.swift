// BoardView.swift — docs/07-games-hub.md §Product rules → "Boards (revised 2026-09-13)".
//
// Friends / Circles only (no Everyone), today-and-yesterday only (no week / all-time),
// one expandable section per game plus "All games" at the top. Ranking is entirely
// client-side (`AppModel.rankRows` / `rankYesterday`); the server's score-based
// `rank` / `prev_rank` are ignored here.

import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct BoardView: View {
    @Environment(AppModel.self) private var model

    @State private var kind: BoardKind = .friends
    /// Today / Yesterday toggle (docs/07 "Added later the same day"), identifier `board.day`.
    @State private var selectedDay: BoardDay = .today
    @State private var expanded: Set<BoardGame> = [.total]
    @State private var reactingTo: String?

    /// Order the sections render in (docs/07): All games first, then the four original
    /// games, then Quint.
    private let sectionGames: [BoardGame] = [.total, .lineup, .stars, .duo, .trail, .quint]

    private var scopeId: String? {
        kind == .circle ? model.selectedCircleId : nil
    }

    /// The date the toggle currently selects: `model.today` or `model.yesterday`.
    private var selectedDate: String {
        selectedDay == .today ? model.today : model.yesterday
    }

    /// The secondary-caption prefix for each row's `prev_*` figure. On Today that figure
    /// is yesterday's; on Yesterday it is the day *before* yesterday's (docs/07 "Added
    /// later the same day").
    private var secondaryPrefix: String {
        selectedDay == .today ? "yesterday" : "day before"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    Picker("Board", selection: $kind) {
                        Text("Friends").tag(BoardKind.friends)
                        Text("Circles").tag(BoardKind.circle)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Which board")
                    .accessibilityIdentifier("board.kind")

                    Picker("Day", selection: $selectedDay) {
                        Text("Today").tag(BoardDay.today)
                        Text("Yesterday").tag(BoardDay.yesterday)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Which day")
                    .accessibilityIdentifier("board.day")

                    if kind == .circle {
                        circleChips
                    }

                    header
                }
                .padding(.horizontal, 16)

                content
            }
            .padding(.top, 8)
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.large)
            .task(id: reloadKey) { await reload(force: false) }
            // Arriving at the board is what completes the "friends found" onboarding
            // step; FriendsFoundStep's button only switches tabs.
            .task { await completeFriendsFoundStep() }
            .refreshable {
                await model.syncContacts(userInitiated: true)
                await reload(force: true)
            }
        }
    }

    private var reloadKey: String {
        "\(kind.rawValue)|\(scopeId ?? "")|\(selectedDay.rawValue)|\(model.today)"
    }

    /// Loads the circle list (if needed) and every currently-expanded section. Called on
    /// appear/kind-change/day-change and by pull-to-refresh; expanding a new section loads
    /// just that one (`ensureLoaded`). Switching the day reloads every already-expanded
    /// section for the newly-selected date (docs/07 "Added later the same day").
    private func reload(force: Bool) async {
        if kind == .circle, model.circles.isEmpty {
            await model.loadCircles()
        }
        // Taunts/reactions are the same for every section (they're keyed by date, not
        // game), so fetch them once here rather than once per expanded section
        // (`refreshBoard(includeSocial:)`, finding C1).
        for game in expanded {
            await model.refreshBoard(kind: kind, scopeId: scopeId, period: .today,
                                     date: selectedDate, game: game, force: force, includeSocial: false)
        }
        await model.refreshSocial()
    }

    /// A method rather than a body inside `.task`; `.task` takes a `@Sendable` closure that
    /// does not inherit this view's `@MainActor` isolation, so the hop is the `await` on
    /// this.
    private func completeFriendsFoundStep() async {
        if model.tail == .friendsFound {
            model.advanceTail()
        }
    }

    /// Loads a section's rows the first time it's expanded; cheap no-op once cached.
    private func ensureLoaded(_ game: BoardGame) async {
        let key = boardKey(for: game)
        if model.boards[key] != nil { return }
        await model.refreshBoard(kind: kind, scopeId: scopeId, period: .today,
                                 date: selectedDate, game: game)
    }

    private func boardKey(for game: BoardGame) -> BoardCacheKey {
        BoardCacheKey(kind: kind, scopeId: scopeId, period: .today, date: selectedDate, game: game)
    }

    private func rawRows(for game: BoardGame) -> [BoardRow] {
        model.boards[boardKey(for: game)] ?? []
    }

    private func expandedBinding(for game: BoardGame) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(game) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(game)
                    Task { await ensureLoaded(game) }
                } else {
                    expanded.remove(game)
                }
            }
        )
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text(headerText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("board.header")
            Spacer()
            if kind == .circle, let circle = model.circles.first(where: { $0.id == model.selectedCircleId }) {
                Button {
                    UIPasteboard.general.string = "KITH-\(circle.code)"
                    model.show(toast: "Code copied.", isError: false)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Copy the circle code")
            }
        }
    }

    /// "Friends · Thursday, Sep 11" or "<circle name> · Thursday, Sep 11" (docs/07: the
    /// header is now the board name + date, not a played-count sentence).
    private var headerText: String {
        let name: String
        switch kind {
        case .friends:
            name = "Friends"
        case .circle:
            name = model.circles.first(where: { $0.id == model.selectedCircleId })?.name ?? "Circle"
        case .everyone:
            name = "Friends"
        }
        return "\(name) · \(AppModel.headerDate(selectedDate))"
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

    // MARK: Sections

    /// "All games" is always expanded/loaded, so its cache entry stands in for "does this
    /// board have anyone on it at all" the way the old single-list `rows` did (findings
    /// B1/B2): `nil` means "not loaded yet" (spinner), a failed key with no cache means
    /// "couldn't load" (retry row), and only an actually-empty `[]` means the empty state.
    private var totalKey: BoardCacheKey { boardKey(for: .total) }

    @ViewBuilder
    private var content: some View {
        if kind == .circle, model.circles.isEmpty {
            emptyState
        } else if model.boards[totalKey] == nil, model.loadingBoards.contains(totalKey) {
            loadingState
        } else if model.boards[totalKey] == nil, model.failedBoards.contains(totalKey) {
            errorState(for: .total)
        } else if (model.boards[totalKey] ?? []).isEmpty {
            emptyState
        } else {
            List {
                // Not a `DisclosureGroup`: inside a List only its chevron toggles, so a tap on
                // the title (and a UI test's tap on `board.section.<slug>`) did nothing. A
                // plain button header plus conditional rows gives the whole header row the
                // toggle and keeps the identifier on one tappable element.
                ForEach(sectionGames, id: \.self) { game in
                    Section {
                        Button {
                            let binding = expandedBinding(for: game)
                            binding.wrappedValue.toggle()
                        } label: {
                            sectionHeaderLabel(for: game)
                        }
                        .buttonStyle(.plain)
                        .tint(sectionColor(for: game))

                        if expanded.contains(game) {
                            sectionRows(for: game)
                        }
                    }
                }
            }
            .listStyle(.plain)
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

    private func sectionTitle(_ game: BoardGame) -> String {
        switch game {
        case .total: return "All games"
        case .lineup: return "Lineup"
        case .stars: return "Stars"
        case .duo: return "Duo"
        case .trail: return "Trail"
        case .quint: return "Quint"
        }
    }

    private func sectionColor(for game: BoardGame) -> Color {
        switch game {
        case .total: return Color.kithAccent
        case .lineup: return Theme.lineup
        case .stars: return Theme.stars
        case .duo: return Theme.duo
        case .trail: return Theme.trail
        case .quint: return Theme.quint
        }
    }

    private func sectionHeaderLabel(for game: BoardGame) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(sectionColor(for: game))
                .frame(width: 24, height: 24)
            Text(sectionTitle(game))
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        // Moved here from the `DisclosureGroup` itself (finding B6): the group's own
        // identifier used to cover its expanded content too, which made the header
        // ambiguous to address once a section was open.
        .accessibilityIdentifier("board.section.\(game.rawValue)")
    }

    @ViewBuilder
    private func sectionRows(for game: BoardGame) -> some View {
        let key = boardKey(for: game)
        if model.loadingBoards.contains(key), model.boards[key] == nil {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 12)
        } else if model.failedBoards.contains(key), model.boards[key] == nil {
            errorState(for: game)
        } else {
            let raw = rawRows(for: game)
            if raw.isEmpty {
                Text("Nobody's played yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                let ranked = AppModel.rankRows(raw, game: game)
                // `uniqueKeysWithValues:` traps on a duplicate user_id; the server is not
                // guaranteed unique here, so fold duplicates instead of crashing (finding A1).
                let yesterdayRank = Dictionary(
                    AppModel.rankYesterday(raw, game: game).map { ($0.row.user_id, $0.rank) },
                    uniquingKeysWith: { first, _ in first }
                )
                ForEach(ranked) { row in
                    BoardRowView(
                        ranked: row,
                        game: game,
                        isMe: row.row.user_id == model.myUserId,
                        name: displayName(for: row.row),
                        movement: movement(rank: row.rank, prevRank: yesterdayRank[row.row.user_id] ?? nil),
                        secondaryPrefix: secondaryPrefix,
                        avatarURL: model.avatarURL(userId: row.row.user_id, version: row.row.avatar_version),
                        // `AppModel.react` always reacts for `today` (finding C7) — rather
                        // than threading a date through it, the Yesterday board simply
                        // makes its rows non-reactable, so the sheet never opens for a day
                        // the reaction wouldn't actually apply to.
                        reactable: selectedDay == .today
                    ) {
                        reactingTo = row.row.user_id
                    }
                    .opacity(row.rank == nil ? 0.55 : 1)
                }
            }
        }
    }

    /// Centred spinner shown while a board's first load (cold tab or a freshly-expanded
    /// section) is in flight (findings B1/B2).
    private var loadingState: some View {
        VStack {
            Spacer(minLength: 0)
            ProgressView()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    /// Shown for a board key whose last load failed and has no cache to fall back on
    /// (findings B1/B2). Retrying re-runs `refreshBoard(force: true)` for just that key.
    private func errorState(for game: BoardGame) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Text("Couldn't load this board.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task {
                    await model.refreshBoard(kind: kind, scopeId: scopeId, period: .today,
                                             date: selectedDate, game: game, force: true)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("board.retry")
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private func movement(rank: Int?, prevRank: Int?) -> RankMovement {
        guard let rank else { return .none }
        guard let prevRank else { return .new }
        switch AppModel.rankMovement(rank: rank, prevRank: prevRank) {
        case .some(let delta) where delta > 0: return .up(delta)
        case .some(let delta) where delta < 0: return .down(-delta)
        default: return .same
        }
    }

    /// The viewer's own row is "You"; everyone else prefers the contact-book name.
    private func displayName(for row: BoardRow) -> String {
        if row.user_id == model.myUserId { return "You" }
        return model.friendNames[row.user_id] ?? row.display_name
    }

    /// Each board is empty for a different reason.
    private var emptyHeadline: String {
        switch kind {
        case .friends, .everyone:
            return "None of your contacts play yet. Be the one who started it."
        case .circle:
            return model.circles.isEmpty
                ? "You're not in a circle yet. Create one or join with a code."
                : "Nobody in this circle has played today."
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
    let ranked: AppModel.RankedBoardRow
    let game: BoardGame
    let isMe: Bool
    let name: String
    let movement: RankMovement
    /// "yesterday" on the Today toggle, "day before" on the Yesterday toggle (docs/07
    /// "Added later the same day").
    var secondaryPrefix: String = "yesterday"
    /// `AppModel.avatarURL(userId:version:)`; nil shows initials.
    var avatarURL: URL? = nil
    /// False on the Yesterday board (finding C7): `AppModel.react` always reacts for
    /// today's date, so a row viewed under the Yesterday toggle can't offer a reaction
    /// that would actually land on the day being looked at.
    var reactable: Bool = true
    let onReact: () -> Void

    // Findings C5: rank column and avatar scale with Dynamic Type instead of staying
    // pinned at a fixed point size.
    @ScaledMetric private var rankWidth: CGFloat = 24
    @ScaledMetric private var avatarSize: CGFloat = 32

    private var row: BoardRow { ranked.row }

    var body: some View {
        HStack(spacing: 10) {
            Text(ranked.rank.map { "\($0)" } ?? "–")
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: rankWidth, alignment: .leading)

            MovementChip(movement: movement)

            AvatarView(name: name, size: avatarSize, highlighted: isMe, url: avatarURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(isMe ? .semibold : .regular))
                    .lineLimit(1)

                Text(AppModel.secondaryLabel(for: row, prefix: secondaryPrefix))
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // docs/07 "Added later the same day": every row's streak, hidden when nil/0.
            if let streak = row.streak, streak > 0 {
                Text("🔥 \(streak)")
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("streak \(streak)")
            }

            // Findings C8: a gave-up/failed row (`attempted`) reads as a dimmer, distinct
            // shade from a solved one, rather than styling every row identically.
            Text(AppModel.timeLabel(for: row, game: game))
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(ranked.attempted ? .tertiary : .secondary)

            if !isMe, ranked.rank != nil, reactable {
                Button {
                    onReact()
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.body)
                        // HIG: a 44 pt target even though the glyph is small.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React to \(name)")
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .overlay(alignment: .leading) {
            if isMe {
                Rectangle()
                    .fill(Color.kithAccent)
                    .frame(width: 3)
                    .offset(x: -12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isMe, ranked.rank != nil, reactable { onReact() }
        }
        // `.contain` rather than `.combine`: the row keeps its own summary label, and the
        // name inside it (notably "You") stays an addressable static text for UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("board.row.\(row.user_id)")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let rank = ranked.rank { parts.append("rank \(rank)") }
        parts.append(name)
        parts.append(AppModel.timeLabel(for: row, game: game))
        parts.append(AppModel.secondaryLabel(for: row, prefix: secondaryPrefix))
        if let streak = row.streak, streak > 0 { parts.append("streak \(streak)") }
        return parts.joined(separator: ", ")
    }
}
