// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeedbackJar
import SwiftUI

@main
struct FeelMacApp: App {
    @State private var model = AppModel()

    init() {
        FeedbackJar.configure(widgetId: "cmw66df8p003wcwp04bsof78i")
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { url in Task { await model.openProject(at: url) } }
        }
        .defaultSize(width: 1360, height: 860)
        .windowToolbarStyle(.unified(showsTitle: true))
        Window("Send Feedback", id: FeedbackCommand.windowID) {
            FeedbackView()
                .frame(width: 420)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .help) { FeedbackCommand() }
            CommandGroup(replacing: .newItem) {
                Button("New Project") { model.newProject() }.keyboardShortcut("n")
                Button("Open…") { model.openProjectPanel() }.keyboardShortcut("o")
                Button("Import Video…") { model.importVideoPanel() }.keyboardShortcut("i")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }.keyboardShortcut("s")
                Button("Save As…") { model.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Duplicate Project") { model.duplicateProject() }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }.keyboardShortcut("z").disabled(!model.canUndo)
                Button("Redo") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo)
            }
            CommandGroup(after: .toolbar) {
                ForEach(Array(StagePanel.allCases.enumerated()), id: \.element) { i, p in
                    Button("Show \(p.title)") { model.toggle(p) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .control])
                }
            }
            CommandMenu("Events") {
                Button("Add Tap") { model.addEvent(.tap) }.keyboardShortcut("1")
                Button("Add Rumble") { model.addEvent(.rumble) }.keyboardShortcut("2")
                Button("Add Tick Train") { model.addEvent(.tickTrain) }.keyboardShortcut("3")
                Divider()
                Button("Duplicate") { model.duplicateSelection() }.keyboardShortcut("d")
                Button("Delete") { model.deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
                Button("Delete (Forward)") { model.deleteSelection() }.keyboardShortcut(.deleteForward, modifiers: [])
                Button("Select All Events") { model.selectAll() }.keyboardShortcut("a", modifiers: [.command, .option])
                Button("Save Selection as Preset…") { model.saveSelectionAsPreset() }.disabled(model.selection.isEmpty)
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("Previous Frame") { model.step(frames: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next Frame") { model.step(frames: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("Go to Start") { model.video.seek(to: 0, precise: true) }.keyboardShortcut(.home, modifiers: [])
                Divider()
                Button("Zoom In") { model.zoom *= 1.25 }.keyboardShortcut("=")
                Button("Zoom Out") { model.zoom /= 1.25 }.keyboardShortcut("-")
            }
        }
    }
}
