// NameStep.swift — docs/03 §1c.
//
// The wireframe asks for a prefill from the device "me" card. iOS has no API for that
// (`CNContactStore.unifiedMeContactWithKeys(toFetch:)` is macOS-only), so the field
// starts empty unless the user is re-registering with a name we already know.

import Foundation
import SwiftUI
import UIKit

@MainActor
struct NameStep: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            Text("What should friends call you?")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                AvatarView(name: model.nameDraft, size: 56, highlighted: true)
                TextField("Your name", text: $model.nameDraft)
                    .textContentType(.name)
                    .font(.title3)
                    .padding(14)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($focused)
                    .accessibilityLabel("Display name")
                    .accessibilityIdentifier("onboarding.name.field")
            }

            Button("Continue") {
                Task { await model.saveName() }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canContinue))
            .disabled(!canContinue)
            .accessibilityLabel("Continue with this name")
            .accessibilityIdentifier("onboarding.name.continue")

            Spacer(minLength: 0)
        }
        .padding(24)
        .onAppear { focused = true }
    }

    private var canContinue: Bool {
        !model.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isBusy
    }
}
