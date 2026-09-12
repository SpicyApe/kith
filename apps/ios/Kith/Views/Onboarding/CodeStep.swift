// CodeStep.swift — docs/03 §1b. Six-digit OTP with SMS autofill, auto-submit on the
// sixth digit, resend disabled for 30 s.

import Foundation
import SwiftUI
import UIKit

@MainActor
struct CodeStep: View {
    let phone: String

    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    private var masked: String {
        guard phone.count > 4 else { return phone }
        return String(phone.prefix(2)) + " ••• ••• " + String(phone.suffix(4))
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            Text("Enter the 6-digit code we sent to \(masked)")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                // The real field is invisible; the six boxes below mirror it.
                TextField("", text: $model.codeDraft)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .opacity(0.02)
                    .accessibilityLabel("Six digit code")
                    .accessibilityIdentifier("onboarding.code.field")

                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        digitBox(at: index)
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    Button {
                        Task { await model.resendCode() }
                    } label: {
                        Text(resendLabel)
                    }
                    .disabled(!canResend)
                    .accessibilityLabel("Resend code")
                    .accessibilityIdentifier("onboarding.code.resend")

                    Spacer()

                    Button("Back") { model.backFromCode() }
                        .accessibilityLabel("Back to phone number")
                }
                .font(.subheadline)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .onAppear { focused = true }
        .onChange(of: model.codeDraft) { _, newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(6))
            if digits != newValue { model.codeDraft = digits }
            if digits.count == 6 {
                focused = false
                Task { await model.verifyCode() }
            }
        }
    }

    private var canResend: Bool {
        guard let at = model.resendAvailableAt else { return true }
        return Date() >= at && !model.isBusy
    }

    private var resendLabel: String {
        guard let at = model.resendAvailableAt else { return "Resend code" }
        let remaining = Int(at.timeIntervalSinceNow.rounded(.up))
        return remaining > 0 ? "Resend code in \(remaining)s" : "Resend code"
    }

    private func digitBox(at index: Int) -> some View {
        let digits = Array(model.codeDraft)
        let character = index < digits.count ? String(digits[index]) : ""
        return Text(character)
            .font(.title.monospacedDigit())
            .frame(width: 44, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(index == digits.count ? Color.kithAccent : Color.clear, lineWidth: 2)
            )
    }
}
