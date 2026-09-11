// OnboardingView.swift — the shell: a four-segment progress bar plus the current step.
// Copy follows docs/03-wireframes.md §1.

import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: model.onboarding.progress)
                .progressViewStyle(.linear)
                .tint(Color.kithAccent)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .accessibilityLabel("Onboarding progress")

            step
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var step: some View {
        switch model.onboarding.step {
        case .phone:
            PhoneStep()
        case .code(let phone):
            CodeStep(phone: phone)
        case .name:
            NameStep()
        case .contactsPrompt:
            ContactsPromptStep()
        case .playing, .done:
            // RootView has already switched to the tab bar by this point.
            Color.clear
        }
    }
}
