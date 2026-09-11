// ResultsView.swift — docs/03 §3. Everything on this screen comes from
// `ResultsPresenter.summary`; the view only lays it out.

import KithCore
import LineupEngine
import Foundation
import SwiftUI
import UIKit

/// One rendered line of the reveal strip, in correct order. File scope, not nested in
/// `ResultsView`, so it does not inherit that view's `@MainActor` isolation and can
/// satisfy `Identifiable`'s nonisolated `id` requirement.
private struct RevealLine: Identifiable {
    let id: Int
    let text: String
}

@MainActor
struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showFacts = false
    @State private var didShare = false
    @FocusState private var tauntFocused: Bool

    var body: some View {
        @Bindable var model = model

        return NavigationStack {
            ScrollView {
                if let summary = model.resultsSummary {
                    VStack(alignment: .leading, spacing: 24) {
                        outcome(summary)
                        AttemptGrid(grid: summary.grid)
                        revealStrip
                        streakLine(summary)
                        rankTeaser(summary)
                        tauntField($model.tauntDraft)
                        shareButtons(summary)
                        footer
                    }
                    .padding(20)
                } else {
                    Text("No result yet.")
                        .font(.headline)
                        .padding(40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { close() }
                        .accessibilityLabel("Close results")
                }
            }
        }
    }

    private func close() {
        model.showResults = false
        dismiss()
        if model.onboarding.step == .playing {
            Task { await model.firstResultShown() }
        }
    }

    // MARK: Sections

    private func outcome(_ summary: ResultsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.headline)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("\(summary.score)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(summary.timeText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score \(summary.score), time \(summary.timeText)")
        }
    }

    /// docs/03 §3: the five items in correct order, each "label · value · fact".
    /// Collapsed to the first two rows; "Show facts" expands the rest.
    private var revealStrip: some View {
        // `model.reveal` needs the gated `list_items` read to have landed. When it
        // hasn't (offline, or the request failed), fall back to labels alone.
        let lines = revealLines

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The order")
                    .font(.headline)
                Spacer()
                if lines.count > 2 {
                    Button(showFacts ? "Hide" : "Show facts") {
                        withAnimation { showFacts.toggle() }
                    }
                    .font(.subheadline)
                    .accessibilityLabel(showFacts ? "Hide the rest of the order" : "Show the whole order and its facts")
                }
            }

            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if showFacts || index < 2 {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .leading)
                        Text(line.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Position \(index + 1): \(line.text)")
                }
            }
        }
        .kithCard()
    }

    private var revealLines: [RevealLine] {
        if model.reveal.isEmpty {
            return model.revealItems.map { RevealLine(id: $0.id, text: $0.label) }
        }
        return model.reveal.map { item in
            var parts = [item.label, AppModel.revealValue(item.value)]
            if let fact = item.fact, !fact.isEmpty { parts.append(fact) }
            return RevealLine(id: item.id, text: parts.joined(separator: " · "))
        }
    }

    private func streakLine(_ summary: ResultsSummary) -> some View {
        Group {
            if summary.streak > 0 {
                Text("🔥 \(summary.streak)-day streak")
                    .font(.headline)
                    .accessibilityLabel("\(summary.streak) day streak")
            }
        }
    }

    @ViewBuilder
    private func rankTeaser(_ summary: ResultsSummary) -> some View {
        if let teaser = summary.rankTeaser {
            Button {
                model.tab = .board
                close()
            } label: {
                HStack {
                    Text(teaser)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .kithCard()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(teaser). Open the board.")
        }
    }

    private func tauntField(_ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Say something to the group (optional)", text: text, axis: .vertical)
                .lineLimit(1...2)
                .focused($tauntFocused)
                // Write-once per day: the server rejects a second insert, so the field
                // closes as soon as one has landed.
                .disabled(model.tauntSaved)
                .foregroundStyle(model.tauntSaved ? Color.secondary : Color.primary)
                .padding(12)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Taunt, optional, 80 characters")
                .onChange(of: text.wrappedValue) { _, newValue in
                    if newValue.count > 80 {
                        text.wrappedValue = String(newValue.prefix(80))
                    }
                }
                .onChange(of: tauntFocused) { _, focused in
                    guard !focused else { return }
                    Task { await model.saveTaunt() }
                }

            Text(model.tauntSaved ? "Saved — one a day" : "\(text.wrappedValue.count)/80")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func shareButtons(_ summary: ResultsSummary) -> some View {
        VStack(spacing: 12) {
            ShareLink(item: summary.shareText) {
                Text(didShare || model.shareCompleted ? "Shared ✓" : "Share")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.kithAccent)
                    )
            }
            .simultaneousGesture(TapGesture().onEnded {
                didShare = true
                model.markShared()
            })
            .accessibilityLabel("Share your result")

            Button("Copy") {
                UIPasteboard.general.string = summary.shareText
                model.show(toast: "Copied.", isError: false)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Copy your result to the clipboard")
        }
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Text("Next puzzle in \(model.countdownText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
