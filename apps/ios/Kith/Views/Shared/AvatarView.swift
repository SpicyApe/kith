// AvatarView.swift — initials in a circle. No image uploads in v1.

import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct AvatarView: View {
    let name: String
    var size: CGFloat = 36
    var highlighted: Bool = false

    private var initials: String {
        BoardPresenter.initials(name)
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(
                SwiftUI.Circle().fill(highlighted ? Color.kithAccent : Color.secondary.opacity(0.18))
            )
            .accessibilityHidden(true)
    }
}
