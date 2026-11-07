// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import SwiftUI

struct SuggestionsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions are starting points. Nothing is added until you accept it.")
                .foregroundStyle(Theme.textSecondary)
            control
            if model.analysisInput != nil {
                FillSlider(
                    label: "Sensitivity",
                    value: Binding(get: { model.sensitivity }, set: { model.sensitivity = $0 }),
                    range: 0...1,
                    format: { "\(Int($0 * 100))%" }
                )
                FlowChips(model: model)
                list
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch model.analysisState {
        case .idle, .done:
            Button(model.analysisInput == nil ? "Analyze video" : "Analyze again") { model.runAnalysis() }
                .buttonStyle(QuietButtonStyle(prominent: model.analysisInput == nil))
                .disabled(model.videoState != .loaded)
        case .running(let p):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: p).tint(Theme.accent)
                HStack {
                    Text("Analyzing \(Int(p * 100))%").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Cancel") { model.cancelAnalysis() }.buttonStyle(QuietButtonStyle())
                }
            }
        case .failed(let msg):
            Text(msg).foregroundStyle(Theme.danger)
            Button("Try again") { model.runAnalysis() }.buttonStyle(QuietButtonStyle())
        }
    }

    private var list: some View {
        let items = model.visibleSuggestions
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(items.count) found").sectionLabel()
                Spacer()
                Button("Reject all") { model.rejectAllVisible() }.buttonStyle(QuietButtonStyle()).disabled(items.isEmpty)
                Button("Accept all") { model.acceptAllVisible() }.buttonStyle(QuietButtonStyle()).disabled(items.isEmpty)
            }
            if items.isEmpty {
                Text("Nothing at this sensitivity. Raise it, or show more kinds.").foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(items) { s in SuggestionRow(model: model, s: s) }
            }
            .padding(.horizontal, -8)
        }
    }
}

private struct SuggestionRow: View {
    let model: AppModel
    let s: HapticSuggestion

    var body: some View {
        HStack(spacing: 4) {
            Button { model.preview(s) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.kind.title).lineLimit(1)
                    Text(Timebase.format(s.time)).font(Theme.fontSmall).monospacedDigit().foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(RowButtonStyle())
            .help(s.reason)
            IconButton(symbol: "xmark", label: "Reject") { model.reject(s) }
            IconButton(symbol: "checkmark", label: "Accept") { model.accept(s) }
        }
    }
}

private struct FlowChips: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Show").sectionLabel()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(SuggestionKind.allCases, id: \.self) { k in
                    let on = model.shownKinds.contains(k)
                    Button(k.title) { model.toggleKind(k) }
                        .buttonStyle(ChipStyle(on: on))
                }
            }
        }
    }
}
