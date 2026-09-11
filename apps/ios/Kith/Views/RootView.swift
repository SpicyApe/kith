// RootView.swift — onboarding or the four tabs.

import Foundation
import SwiftUI
import UIKit

@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if !AppConfig.isConfigured {
                configBanner
            }
            Group {
                switch model.stage {
                case .launching:
                    LaunchView()
                case .signedOut, .registering:
                    OnboardingView()
                case .ready:
                    // The contacts pre-prompt is the one onboarding step that runs after
                    // registration has succeeded (docs/02 §6 step 4).
                    if model.onboarding.step == .contactsPrompt {
                        OnboardingView()
                    } else if model.showContactsReask {
                        // The one-time second ask, for a regular who skipped it at
                        // onboarding. Shown bare rather than through `OnboardingView`,
                        // which would also redraw the four-segment progress bar — so it
                        // needs that shell's fill and background here.
                        ContactsPromptStep()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    } else {
                        MainTabs()
                    }
                }
            }
        }
        .toast(model.toast)
        .fullScreenCover(isPresented: .constant(model.tail != .none)) {
            OnboardingTailView()
        }
    }

    /// Without a `Config.plist` every request goes to a placeholder host and fails with
    /// an unhelpful network error. Say so at the top of the screen instead.
    private var configBanner: some View {
        Text("Config.plist missing — see apps/ios/README")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.85))
            .accessibilityLabel("Configuration missing. See the apps slash ios README.")
    }
}

@MainActor
private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Kith")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Color.kithAccent)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityLabel("Loading Kith")
    }
}

@MainActor
private struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "square.stack.3d.up") }
                .tag(AppTab.today)

            BoardView()
                .tabItem { Label("Board", systemImage: "list.number") }
                .tag(AppTab.board)

            CirclesView()
                .tabItem { Label("Circles", systemImage: "person.3") }
                .tag(AppTab.circles)

            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(AppTab.you)
        }
    }
}

/// docs/02 §6 steps 7 and 8: friends found, then the notification pre-prompt.
@MainActor
private struct OnboardingTailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.tail {
        case .friendsFound:
            FriendsFoundStep()
        case .notifications:
            NotificationsPromptStep()
        case .none:
            Color.clear
        }
    }
}
