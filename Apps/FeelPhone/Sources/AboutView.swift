// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import SwiftUI

/// Privacy summary for the app. Same words as PRIVACY.md.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedback = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Text("Feel does not collect your data. It has no account, no analytics, no ads, and no tracking.")
                    Text("Videos stay on your device. Feel makes haptics from the sound on your device.")
                    Text("The camera scans the QR code on your Mac. The image is not saved or sent.")
                    Text("The local network link goes only to your own Mac. It is encrypted.")
                    Text("Feedback is optional. If you send it, the text you type goes to FeedbackJar, with your device model, OS version, and app version. A name and email are optional.")
                }
                Section("Feedback") {
                    Button("Send feedback") { feedback = true }
                    Link("Read the privacy policy", destination: URL(string: "https://github.com/mcnaveen/feel/blob/main/PRIVACY.md")!)
                }
                Section("License") {
                    Text("Copyright © 2026 7 Angle.")
                    Text("Feel is free software under the GNU AGPL 3.0 or later.")
                    Text("The AGPL does not apply to the Feel names and icons. All rights reserved.")
                    Link("View the source code on GitHub", destination: URL(string: "https://github.com/mcnaveen/feel")!)
                    Link("Read the license", destination: URL(string: "https://github.com/mcnaveen/feel/blob/main/LICENSE")!)
                }
                Section("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("About Feel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $feedback) { FeedbackView() }
        }
    }
}
