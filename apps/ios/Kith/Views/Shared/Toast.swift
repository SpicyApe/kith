// Toast.swift — the one transient message surface ("Finding your friends…",
// "3 friends found", "Offline. Your score will sync.").

import Foundation
import SwiftUI
import UIKit

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        Text(message.text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(message.isError ? Color.red.opacity(0.9) : Color.black.opacity(0.85))
            )
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("toast")
    }
}

private struct ToastModifier: ViewModifier {
    let message: ToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                ToastView(message: message)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

extension View {
    func toast(_ message: ToastMessage?) -> some View {
        modifier(ToastModifier(message: message))
    }
}
