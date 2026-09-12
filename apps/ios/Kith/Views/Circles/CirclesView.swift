// CirclesView.swift — docs/03 §4 (circles tab) and docs/02 §3.

import KithCore
import Foundation
import SwiftUI
import UIKit

@MainActor
struct CirclesView: View {
    @Environment(AppModel.self) private var model

    @State private var newCircleName = ""
    @State private var joinCode = ""
    @State private var pendingLeave: KithCore.Circle?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section {
                    if model.circles.isEmpty {
                        Text("You're not in any circles yet. Create one for the group chat, or join with a code.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(model.circles) { circle in
                            row(for: circle)
                        }
                    }
                } header: {
                    Text("Your circles")
                }

                Section {
                    Button("Create a circle") { model.showCreateCircleSheet = true }
                        .accessibilityLabel("Create a circle")
                        .accessibilityIdentifier("circles.new")
                    Button("Join with a code") { model.showJoinSheet = true }
                        .accessibilityLabel("Join a circle with a code")
                        .accessibilityIdentifier("circles.join")
                }
            }
            .navigationTitle("Circles")
            .task { await model.loadCircles() }
            .refreshable { await model.loadCircles() }
            .sheet(isPresented: $model.showCreateCircleSheet) { createSheet }
            .sheet(isPresented: $model.showJoinSheet) { joinSheet }
            .confirmationDialog(
                "Leave this circle?",
                isPresented: Binding(
                    get: { pendingLeave != nil },
                    set: { if !$0 { pendingLeave = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    if let circle = pendingLeave {
                        Task { await model.leaveCircle(id: circle.id) }
                    }
                    pendingLeave = nil
                }
                Button("Cancel", role: .cancel) { pendingLeave = nil }
            }
        }
    }

    private func row(for circle: KithCore.Circle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(circle.name)
                    .font(.body.weight(.medium))
                Spacer()
                Button("Open") {
                    model.selectedCircleId = circle.id
                    model.tab = .board
                }
                .font(.subheadline)
                .accessibilityLabel("Open the \(circle.name) board")
            }

            HStack(spacing: 12) {
                Text("KITH-\(circle.code)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)

                Button {
                    UIPasteboard.general.string = "KITH-\(circle.code)"
                    model.show(toast: "Code copied.", isError: false)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy the code for \(circle.name)")

                ShareLink(item: model.circleLink(circle)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share a link to \(circle.name)")

                Spacer()

                Button("Leave") { pendingLeave = circle }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Leave \(circle.name)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("circles.chip.\(circle.code)")
    }

    // MARK: Sheets

    private var createSheet: some View {
        NavigationStack {
            Form {
                TextField("Name (up to 24 characters)", text: $newCircleName)
                    .accessibilityLabel("Circle name")
                Text("\(newCircleName.count)/24")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("New circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.showCreateCircleSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newCircleName
                        newCircleName = ""
                        Task { await model.createCircle(name: name) }
                    }
                    .disabled(newCircleName.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var joinSheet: some View {
        NavigationStack {
            Form {
                TextField("KITH-7F3Q", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Circle join code")
                    .accessibilityIdentifier("circles.join.field")
            }
            .navigationTitle("Join a circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.showJoinSheet = false
                        model.pendingJoinCode = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        let code = joinCode
                        Task { await model.joinCircle(code: code) }
                    }
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                    .accessibilityIdentifier("circles.join.submit")
                }
            }
            .onAppear {
                if let pending = model.pendingJoinCode, joinCode.isEmpty {
                    joinCode = "KITH-" + pending
                }
            }
        }
        .presentationDetents([.medium])
    }
}
