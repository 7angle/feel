// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import SwiftUI

@main
struct FeelPlayerApp: App {
    @State private var model = PlayerModel()

    var body: some Scene {
        WindowGroup {
            PlayerRootView(model: model)
                .frame(minWidth: 640, minHeight: 420)
                .onOpenURL { url in Task { await model.open(url) } }
        }
        .defaultSize(width: 1000, height: 640)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openPanel() }.keyboardShortcut("o")
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("Back 10 Seconds") { model.skip(by: -10) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Forward 10 Seconds") { model.skip(by: 10) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("Go to Start") { model.video.seek(to: 0, precise: true) }.keyboardShortcut(.home, modifiers: [])
            }
        }
    }
}
