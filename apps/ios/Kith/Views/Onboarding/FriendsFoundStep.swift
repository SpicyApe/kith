// FriendsFoundStep.swift — docs/03 §1 "post-play onboarding tail".

import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct FriendsFoundStep: View {
    @Environment(AppModel.self) private var model

    private var rows: [BoardDisplayRow] { model.friendPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            if rows.isEmpty {
                emptyState
            } else {
                foundState
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Color(.systemBackground))
    }

    private var foundState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(headline)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        AvatarView(name: row.name)
                        Text(row.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Text(row.played ? "\(row.score)" : "hasn't played yet")
                            .font(.subheadline)
                            .foregroundStyle(row.played ? Color.primary : Color.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            // No `advanceTail()` here: the board's own `.task` advances the tail once
            // BoardView has actually appeared, so the notification pre-prompt never
            // covers a board that is still loading.
            Button("See the board") {
                model.tab = .board
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("See the board")
            .accessibilityIdentifier("onboarding.friends.seeBoard")
        }
    }

    private var headline: String {
        let count = rows.count
        return count == 1 ? "1 of your contacts already plays" : "\(count) of your contacts already play"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("None of your contacts play yet. You're first.")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ShareLink(item: inviteText) {
                Text("Invite the group chat")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.kithAccent)
                    )
            }
            .accessibilityLabel("Invite the group chat")
            .accessibilityIdentifier("onboarding.friends.invite")

            Button("Create a circle") {
                model.showCreateCircleSheet = true
                model.tab = .circles
                model.advanceTail()
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Create a circle")
            .accessibilityIdentifier("onboarding.friends.createCircle")

            Button("Have a code?") {
                model.showJoinSheet = true
                model.tab = .circles
                model.advanceTail()
            }
            .font(.subheadline)
            .accessibilityLabel("I have a join code")

            Button("Skip") { model.advanceTail() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Skip for now")
        }
    }

    private var inviteText: String {
        InvitePresenter.text(
            webBase: AppConfig.webBase.absoluteString,
            code: model.profile?.invite_code ?? "",
            puzzleNumber: model.puzzle?.number
        )
    }
}
