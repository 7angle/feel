// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AppKit
import FeelCore
import SwiftUI

struct ExportButton: View {
    let model: AppModel
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { Text("Export").padding(.horizontal, 4) }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .help("Export haptics")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ExportPanel(model: model, close: { open = false }).frame(width: 272)
            }
    }
}

private struct ExportPanel: View {
    let model: AppModel
    let close: () -> Void
    @State private var formats: Set<ExportFormat> = Set(ExportFormat.allCases)
    @State private var result: Result<[URL], Error>?

    private var issues: [ExportIssue] { ExportEngine.validate(model.project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export haptics").fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ExportFormat.allCases, id: \.self) { f in
                    Toggle(f.title, isOn: Binding(
                        get: { formats.contains(f) },
                        set: { on in if on { formats.insert(f) } else { formats.remove(f) } }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, i in
                        Label(i.message, systemImage: i.severity == .error ? "xmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(i.severity == .error ? Theme.danger : Theme.textSecondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            if case .success(let urls)? = result {
                Text("Wrote \(urls.count) file\(urls.count == 1 ? "" : "s").").foregroundStyle(Theme.textSecondary)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }.buttonStyle(QuietButtonStyle())
            } else if case .failure(let e)? = result {
                Text(e.localizedDescription).foregroundStyle(Theme.danger)
            }
            HStack {
                Spacer()
                Button("Export…", action: export)
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .disabled(formats.isEmpty || ExportEngine.hasErrors(issues))
            }
        }
        .font(Theme.font)
        .padding(16)
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        result = Result { try ExportEngine.write(model.project, formats: formats, to: dir) }
    }
}
