// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeedbackJar
import SwiftUI

/// Help menu item that opens the feedback window.
struct FeedbackCommand: View {
    static let windowID = "feedback"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Send Feedback…") { openWindow(id: Self.windowID) }
    }
}

/// A short form. The text goes to FeedbackJar only when the user clicks Send.
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
        VStack(alignment: .leading, spacing: 12) {
            if sent {
                Text("Thank you.").font(.title3.weight(.semibold))
                Text("Your feedback is sent.").foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Send feedback").font(.title3.weight(.semibold))
                TextEditor(text: $text)
                    .font(.body)
                    .frame(height: 140)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .disabled(sending)
                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(sending)
                TextField("Email (optional)", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(sending)
                Text("Your text goes to FeedbackJar with your Mac model, macOS version, and app version. If you add a name or email, it goes too. The developer can then reply to you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if failed {
                    Text("Cannot send. Check your connection and try again.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Send", action: send)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!valid || sending)
                }
            }
        }
        .padding(20)
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
