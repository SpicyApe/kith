// Theme.swift — the three colours and two shapes the app actually uses.

import Foundation
import SwiftUI
import UIKit

// Computed `static var`, not `static let`: a stored static on `Color` is a global
// initialised lazily on first touch, which under strict concurrency is a shared
// mutable state warning, and `Color(.secondarySystemBackground)` should be re-read
// rather than frozen at first use anyway.
extension Color {
    /// Warm coral. Lives in Assets.xcassets so the tab bar and system controls pick it up.
    static var kithAccent: Color { Color("AccentColor") }

    static var tileNeutral: Color { Color(.secondarySystemBackground) }
    static var tileCorrect: Color { Color.green.opacity(0.28) }
    static var tileNear: Color { Color.yellow.opacity(0.35) }

    static var cardBackground: Color { Color(.secondarySystemBackground) }
}

extension View {
    /// Rounded card used by the prompt, results and board sections.
    func kithCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Big primary button, matching the wireframes' single accent.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? Color.kithAccent : Color.gray.opacity(0.4))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Same size as the primary button, outline only (docs/02 §2 insists on this).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.primary)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
