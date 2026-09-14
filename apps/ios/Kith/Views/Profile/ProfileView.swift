// ProfileView.swift — docs/03 §5.

import GridGames
import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var showEditProfile = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section { headerRow }

                Section("Last 8 weeks") {
                    HeatmapView(cells: model.heatmap)
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("profile.heatmap")
                }

                Section("Stats") {
                    StatsGrid(stats: model.stats)
                        .padding(.vertical, 4)
                }

                // The invite code stays above the per-game stats: it is the one row on this
                // screen people act on (docs/02 §6 "find friends"), and keeping it in the
                // first screenful is also what lets the UI tests find it without scrolling.
                if let profile = model.profile {
                    Section("Your code") {
                        HStack {
                            // The visible text keeps the "KITH-" prefix people type, but
                            // the accessibility label is the raw code the API returned,
                            // which is what KithUITests matches on.
                            Text("KITH-\(profile.invite_code)")
                                .font(.body.monospaced())
                                .accessibilityLabel("Invite code \(profile.invite_code)")
                                .accessibilityIdentifier("profile.inviteCode")
                            Spacer()
                            ShareLink(item: inviteText(profile.invite_code)) {
                                Text("Share")
                            }
                            .accessibilityLabel("Share your invite code")
                        }
                    }
                }

                gamesSection

                notificationsSection
                contactsSection
                circlesSection
                privacySection
                dangerSection

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(AppConfig.appVersion)")
                        Text("Made by two people who lose to their mums every day.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.large)
            .task { await model.loadProfileData() }
            .refreshable { await model.loadProfileData() }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(currentName: model.profile?.display_name ?? "")
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $model.showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await model.deleteAccount() }
                }
                .accessibilityIdentifier("profile.deleteConfirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("""
                This is immediate and cannot be undone. It deletes your profile, every result \
                and streak, your contact hashes, your circle memberships, your reactions and \
                taunts, and any device registered for notifications.
                """)
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 14) {
            AvatarView(
                name: model.profile?.display_name ?? "?", size: 56, highlighted: true,
                url: model.avatarURL(userId: model.myUserId, version: model.profile?.avatar_version)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(model.profile?.display_name ?? "You")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("profile.name")
                Text("Best: \(model.stats.longestStreak)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showEditProfile = true
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit profile")
            .accessibilityIdentifier("profile.edit")

            Text("🔥 \(model.streak)")
                .font(.headline.monospacedDigit())
                .accessibilityLabel("Current streak \(model.streak) days")
                .accessibilityIdentifier("profile.streak")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func inviteText(_ code: String) -> String {
        // No puzzle number here: the profile invite is an evergreen "join me" link, not
        // a pointer at today's puzzle.
        InvitePresenter.text(webBase: AppConfig.webBase.absoluteString, code: code, puzzleNumber: nil)
    }

    /// docs/07: days played and best time per grid game.
    private var gamesSection: some View {
        Section("Games") {
            ForEach(model.gameStats) { stat in
                HStack(spacing: 12) {
                    Image(systemName: stat.game.symbolName)
                        .font(.body)
                        .foregroundStyle(Color.kithAccent)
                        .frame(width: 28)
                    Text(stat.game.title)
                        .font(.body)
                    Spacer()
                    Text(Self.gameStatText(stat))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(stat.game.title): \(Self.gameStatText(stat))")
                .accessibilityIdentifier("profile.game.\(stat.game.rawValue)")
            }
        }
    }

    private static func gameStatText(_ stat: GameStat) -> String {
        guard stat.daysPlayed > 0 else { return "Not played yet" }
        let days = stat.daysPlayed == 1 ? "1 day" : "\(stat.daysPlayed) days"
        guard let best = stat.bestMs else { return days }
        return "\(days) · best \(AppModel.clock(best))"
    }

    // MARK: Settings sections

    @ViewBuilder
    private var notificationsSection: some View {
        if let profile = model.profile {
            Section("Notifications") {
                Toggle("Daily drop", isOn: Binding(
                    get: { profile.push_daily },
                    set: { value in Task { await model.updateProfile(ProfilePatch(push_daily: value)) } }
                ))
                .accessibilityLabel("Daily drop notification")

                LabeledContent("Time", value: String(profile.push_daily_at.prefix(5)))
                    .accessibilityLabel("Daily drop time \(String(profile.push_daily_at.prefix(5)))")

                Toggle("Streak at risk", isOn: Binding(
                    get: { profile.push_streak },
                    set: { value in Task { await model.updateProfile(ProfilePatch(push_streak: value)) } }
                ))
                .accessibilityLabel("Streak at risk notification")

                Toggle("Passed on the board", isOn: Binding(
                    get: { profile.push_passed },
                    set: { value in Task { await model.updateProfile(ProfilePatch(push_passed: value)) } }
                ))
                .accessibilityLabel("Passed on the board notification")
            }
        }
    }

    @ViewBuilder
    private var contactsSection: some View {
        Section("Contacts") {
            Text(model.contactsStatusLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if model.contactsState.allowsFetch {
                Button("Sync now") {
                    Task { await model.syncContacts(userInitiated: true) }
                }
                .disabled(model.isSyncingContacts)
                .accessibilityLabel("Sync contacts now")
            } else {
                Button("Turn on contacts") { openSettings() }
                    .accessibilityLabel("Open Settings to turn on contacts")
            }

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

            if let profile = model.profile {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Let contacts find me", isOn: Binding(
                        get: { profile.discoverable },
                        set: { value in Task { await model.updateProfile(ProfilePatch(discoverable: value)) } }
                    ))
                    .accessibilityLabel("Let contacts find me")
                    .accessibilityIdentifier("profile.discoverable")
                    Text("Off means you never appear in anyone's matches and your hashes are deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var circlesSection: some View {
        Section("Circles") {
            if model.circles.isEmpty {
                Text("None yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.circles) { circle in
                    HStack {
                        Text(circle.name)
                        Spacer()
                        Button("Leave") {
                            Task { await model.leaveCircle(id: circle.id) }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Leave \(circle.name)")
                    }
                }
            }
            Button("Manage circles") { model.tab = .circles }
                .accessibilityLabel("Manage circles")
        }
    }

    private var privacySection: some View {
        Section {
            Link("Privacy policy", destination: AppConfig.webBase.appendingPathComponent("privacy"))
            Link("Terms", destination: AppConfig.webBase.appendingPathComponent("terms"))
            Link("How matching works", destination: AppConfig.webBase.appendingPathComponent("matching"))
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Sign out") {
                Task { await model.signOut() }
            }
            .accessibilityLabel("Sign out")

            Button("Delete account", role: .destructive) {
                model.showDeleteConfirm = true
            }
            .accessibilityLabel("Delete my account")
            .accessibilityIdentifier("profile.deleteAccount")
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Heatmap

/// 8 columns × 7 rows, oldest first, Monday-start weeks (`ProfilePresenter.heatmap`).
@MainActor
struct HeatmapView: View {
    let cells: [HeatCell]

    private let columns = 8
    private let rows = 7

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(spacing: 4) {
                    ForEach(0..<rows, id: \.self) { row in
                        let index = column * rows + row
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(at: index))
                            .frame(width: 14, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(isToday(index) ? Color.kithAccent : Color.clear, lineWidth: 1.5)
                            )
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel)
    }

    private func cell(at index: Int) -> HeatCell {
        index >= 0 && index < cells.count ? cells[index] : .future
    }

    private func color(at index: Int) -> Color {
        switch cell(at: index) {
        case .missed: return Color.secondary.opacity(0.12)
        case .played: return Color.kithAccent.opacity(0.45)
        case .solvedFirstTry: return Color.kithAccent
        case .future: return Color.secondary.opacity(0.05)
        }
    }

    /// The last non-future cell is today.
    private func isToday(_ index: Int) -> Bool {
        guard let last = cells.lastIndex(where: { $0 != .future }) else { return false }
        return index == last
    }

    private var summaryLabel: String {
        let played = cells.filter { $0 == .played || $0 == .solvedFirstTry }.count
        let firstTry = cells.filter { $0 == .solvedFirstTry }.count
        return "Last 8 weeks: played \(played) days, solved \(firstTry) on the first try"
    }
}

// MARK: - Stats

@MainActor
struct StatsGrid: View {
    let stats: ProfileStats

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            tile("Days played", "\(stats.daysPlayed)")
            tile("Solve rate", "\(Int((stats.solveRate * 100).rounded()))%")
            tile("Avg score", "\(stats.averageScore)")
            histogram
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    private var histogram: some View {
        let counts = stats.triesHistogram
        let maximum = max(counts.max() ?? 1, 1)
        let labels = ["1", "2", "3", "✗"]

        return VStack(alignment: .leading, spacing: 4) {
            Text("Tries")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<min(counts.count, 4), id: \.self) { index in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.kithAccent.opacity(index == 3 ? 0.35 : 0.8))
                            .frame(width: 12, height: max(3, CGFloat(counts[index]) / CGFloat(maximum) * 32))
                        Text(labels[index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(histogramLabel)
    }

    private var histogramLabel: String {
        let counts = stats.triesHistogram
        guard counts.count >= 4 else { return "Tries distribution" }
        return "Tries: \(counts[0]) in one, \(counts[1]) in two, \(counts[2]) in three, \(counts[3]) failed"
    }
}
