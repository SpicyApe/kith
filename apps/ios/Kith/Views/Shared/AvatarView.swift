// AvatarView.swift — initials in a circle, or the member's picture when they have one
// (migration 0009 / docs/07 "Profile (2026-09-13)").

import KithCore
import Foundation
import SwiftUI

@MainActor
struct AvatarView: View {
    let name: String
    var size: CGFloat = 36
    var highlighted: Bool = false
    /// `AppModel.avatarURL(userId:version:)`; nil shows the initials placeholder (also
    /// nil for the fakes, so `KithTests`/`KithUITests` stay offline).
    var url: URL? = nil

    private var initials: String {
        BoardPresenter.initials(name)
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(SwiftUI.Circle())
                    default:
                        // Placeholder while loading, and the fallback on failure.
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .accessibilityHidden(true)
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(
                SwiftUI.Circle().fill(highlighted ? Color.kithAccent : Color.secondary.opacity(0.18))
            )
    }
}
