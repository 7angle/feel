// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeedbackJar
import SwiftUI

@main
struct FeelPhoneApp: App {
    @State private var model = CompanionModel()
    @Environment(\.scenePhase) private var phase

    init() {
        FeedbackJar.configure(widgetId: "cmw66df8p003wcwp04bsof78i")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { model.start() }
                .onChange(of: phase) { _, new in if new == .active { model.resume() } }
        }
    }
}
