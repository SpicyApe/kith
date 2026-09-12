// PhoneStep.swift — docs/03 §1a.

import Foundation
import SwiftUI
import UIKit

@MainActor
struct PhoneStep: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("Kith")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.kithAccent)
                Text("One puzzle a day. Ranked against people you actually know.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("+1 555 123 4567", text: $model.phoneDraft)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .font(.title3)
                .padding(14)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .accessibilityLabel("Phone number, including country code")
                .accessibilityIdentifier("onboarding.phone.field")

            Button("Continue") {
                Task { await model.sendCode() }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !model.isBusy))
            .disabled(model.isBusy)
            .accessibilityLabel("Continue and send me a code")
            .accessibilityIdentifier("onboarding.phone.continue")

            Text("We'll text you a code. Standard rates apply.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Link("Terms", destination: AppConfig.webBase.appendingPathComponent("terms"))
                Text("·").foregroundStyle(.secondary)
                Link("Privacy", destination: AppConfig.webBase.appendingPathComponent("privacy"))
            }
            .font(.footnote)

            Spacer(minLength: 0)
        }
        .padding(24)
        .onAppear { focused = true }
    }
}
