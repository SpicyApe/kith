// ContactsPromptStep.swift — docs/03 §1d, docs/02 §2. The OS dialog is only ever
// fired from "Find my friends"; "Not now" is a real, equally sized option.

import Foundation
import SwiftUI
import UIKit

@MainActor
struct ContactsPromptStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            illustration

            Text("See which of your contacts already play.")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Numbers are hashed on your phone.")
                bullet("Names never leave your phone.")
                bullet("We never message anyone for you.")
            }

            Spacer(minLength: 0)

            Button("Find my friends") {
                Task { await model.requestContactsAccess() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("Find my friends using my contacts")
            .accessibilityIdentifier("onboarding.contacts.allow")

            Button("Not now") {
                model.declineContacts()
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Skip contacts for now")
            .accessibilityIdentifier("onboarding.contacts.notNow")
        }
        .padding(24)
    }

    private var illustration: some View {
        HStack(spacing: -10) {
            ForEach(Array(["AB", "CD", "EF"].enumerated()), id: \.offset) { index, initials in
                ZStack(alignment: .bottomTrailing) {
                    Text(initials)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.kithAccent))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("·").foregroundStyle(Color.kithAccent)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
