// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import SwiftUI

struct StagePanelCard: View {
    @Bindable var model: AppModel
    let panel: StagePanel

    var body: some View {
        HugScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text(panel.title).fontWeight(.semibold)
                switch panel {
                case .library: LibraryPanel(model: model)
                case .suggest: SuggestionsView(model: model)
                case .project: ProjectPanel(model: model)
                }
            }
            .padding(14)
            .frame(width: 272, alignment: .leading)
        }
        .floating()
    }
}

private struct LibraryPanel: View {
    let model: AppModel

    private static let samples: [(HapticEventType, String, [HapticEvent])] = [
        (.tap, "Tap", [HapticEvent(type: .tap, start: 0.1, intensity: 1)]),
        (.rumble, "Rumble", [HapticEvent(type: .rumble, start: 0, duration: 0.3, intensity: 0.8, fadeIn: 0.1, fadeOut: 0.15)]),
        (.tickTrain, "Ticks", [HapticEvent(type: .tickTrain, start: 0, intensity: 0.8, repetitionInterval: 0.08, repetitionCount: 4)]),
    ]

    private var hint: String {
        let add = "Press + or drag to the timeline to add."
        return model.session.isConnected ? "Click to feel it on your phone. \(add)" : "Connect a phone to feel these. \(add)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(hint)
                .font(Theme.fontSmall)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(Self.samples, id: \.0) { type, title, events in
                    Button { model.audition(sequence: events) } label: {
                        VStack(spacing: 8) {
                            HapticSignature(events: events).frame(width: 44, height: 20)
                            Text(title).font(Theme.fontSmall)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(Theme.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TileStyle())
                    .help("Feel \(title.lowercased()) on your phone")
                    .accessibilityLabel("Feel \(title)")
                    .overlay(alignment: .topTrailing) {
                        IconButton(symbol: "plus", label: "Add \(title.lowercased()) at the playhead", size: 22) { model.addEvent(type) }
                            .font(Theme.fontSmall)
                            .padding(2)
                    }
                    .draggable(LibraryItem.type(type).payload) { DragChip(title: title, events: events) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets").sectionLabel()
                VStack(spacing: 0) {
                    ForEach(model.allPresets) { preset in
                        HStack(spacing: 2) {
                            Button { model.audition(sequence: preset.events) } label: {
                                HStack(spacing: 8) {
                                    Text(preset.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    HapticSignature(events: preset.events, opacity: 0.7).frame(width: 56, height: 16)
                                }
                            }
                            .buttonStyle(RowButtonStyle())
                            .help("Feel \(preset.name) on your phone")
                            .accessibilityLabel("Feel \(preset.name)")
                            IconButton(symbol: "plus", label: "Add \(preset.name) at the playhead", size: 26) { model.insert(preset) }
                        }
                        .draggable(LibraryItem.preset(preset.id).payload) { DragChip(title: preset.name, events: preset.events) }
                        .contextMenu {
                            Button("Add at Playhead") { model.insert(preset) }
                            if !preset.isBuiltIn { Button("Delete") { model.deleteCustomPreset(preset.id) } }
                        }
                    }
                }
                .padding(.horizontal, -8)
            }
            Button("Save Selection as Preset…") { model.saveSelectionAsPreset() }
                .buttonStyle(QuietButtonStyle())
                .padding(.horizontal, -8)
                .disabled(model.selection.isEmpty)
        }
    }
}

/// What follows the pointer during a drag.
private struct DragChip: View {
    let title: String
    let events: [HapticEvent]

    var body: some View {
        HStack(spacing: 8) {
            HapticSignature(events: events).frame(width: 40, height: 16)
            Text(title).font(Theme.font).foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.deck, in: Capsule())
        .overlay(Capsule().stroke(Theme.border))
    }
}

private struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

private struct ProjectPanel: View {
    @Bindable var model: AppModel
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .controlRow()
                    .onSubmit { model.rename(to: name) }
                    .onAppear { name = model.project.name }
                    .onChange(of: model.project.name) { _, new in name = new }
                row("Autosave", Toggle("Autosave", isOn: $model.project.settings.autosave).labelsHidden().toggleStyle(.switch).controlSize(.mini))
                row("Snap to grid", Toggle("Snap to grid", isOn: $model.project.settings.snapToGrid).labelsHidden().toggleStyle(.switch).controlSize(.mini))
            }
            if let v = model.project.video {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video").sectionLabel()
                    row("File", Text(v.url.lastPathComponent).lineLimit(1).truncationMode(.middle))
                    row("Duration", Text(Timebase.format(v.metadata.duration)).monospacedDigit())
                    row("Frame rate", Text(String(format: "%.2f fps", v.metadata.frameRate)).monospacedDigit())
                    row("Resolution", Text(v.metadata.resolutionLabel).monospacedDigit())
                }
            }
        }
    }

    private func row<V: View>(_ label: String, _ value: V) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary).fixedSize()
            Spacer(minLength: 12)
            value
        }
    }
}
