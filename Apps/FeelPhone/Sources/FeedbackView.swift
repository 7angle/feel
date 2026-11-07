// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeedbackJar
import SwiftUI

/// A short form. The text goes to FeedbackJar only when the user taps Send.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var name = FeedbackJar.shared.getIdentity().name ?? ""
    @State private var email = FeedbackJar.shared.getIdentity().email ?? ""
    @State private var sending = false
    @State private var sent = false
    @State private var failed = false

    private var message: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanName: String? { Self.clean(name) }
    private var cleanEmail: String? { Self.clean(email) }
    /// Name and email are optional. An email, if given, needs an @.
    private var valid: Bool { !message.isEmpty && (cleanEmail?.contains("@") ?? true) }

    private static func clean(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    var body: some View {
        NavigationStack {
            Group {
                if sent {
                    VStack(spacing: 8) {
                        Text("Thank you.").font(.title3.weight(.semibold))
                        Text("Your feedback is sent.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section {
                            TextEditor(text: $text)
                                .frame(minHeight: 160)
                                .disabled(sending)
                        }
                        Section {
                            TextField("Name (optional)", text: $name)
                                .textContentType(.name)
                                .disabled(sending)
                            TextField("Email (optional)", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(sending)
                        } footer: {
                            Text("Your text goes to FeedbackJar with your device model, OS version, and app version. If you add a name or email, it goes too. The developer can then reply to you.")
                        }
                        if failed {
                            Section { Text("Cannot send. Check your connection and try again.").foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send", action: send).disabled(!valid || sending)
                    }
                }
            }
        }
    }

    private func send() {
        sending = true
        failed = false
        Task {
            let result = await FeedbackJar.shared.submit(message, email: cleanEmail, name: cleanName)
            sending = false
            switch result {
            case .success: sent = true
            case .failure: failed = true
            }
        }
    }
}
