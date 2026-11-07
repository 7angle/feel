// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import SwiftUI

/// Privacy summary for the app. Same words as PRIVACY.md.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Text("Feel does not collect your data. It has no account, no analytics, no ads, and no tracking.")
                    Text("Videos stay on your device. Feel makes haptics from the sound on your device.")
                    Text("The camera scans the QR code on your Mac. The image is not saved or sent.")
                    Text("The local network link goes only to your own Mac. It is encrypted.")
                }
                Section("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("About Feel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
