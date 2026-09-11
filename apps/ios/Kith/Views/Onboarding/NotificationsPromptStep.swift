// NotificationsPromptStep.swift — docs/02 §7, docs/03 §1. Only "Yes" fires the OS prompt.

import Foundation
import SwiftUI
import UIKit

@MainActor
struct NotificationsPromptStep: View {
    @Environment(AppModel.self) private var model
    @State private var showTimePicker = false
    @State private var pickedTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            Text("Want a nudge when the next puzzle drops?")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("One notification a day, at a time you choose. Never marketing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                Task { await model.enableNotifications() }
            } label: {
                Text("Yes, at \(model.notificationTime)")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("Yes, remind me at \(model.notificationTime)")

            Button("Change the time") { showTimePicker = true }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Change the reminder time")

            Button("No thanks") { model.tail = .none }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("No notifications")
        }
        .padding(24)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                DatePicker(
                    "Daily reminder",
                    selection: $pickedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .navigationTitle("Daily reminder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            model.notificationTime = Self.hhmm(from: pickedTime)
                            showTimePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    static func hhmm(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 8
        let minute = parts.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }
}
