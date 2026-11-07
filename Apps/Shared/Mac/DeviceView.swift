// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import CoreImage.CIFilterBuiltins
import FeelCore
import SwiftUI

/// What the phone panel needs from the app that owns the devices.
@MainActor
protocol DeviceHost: AnyObject {
    var session: DeviceSession { get }
    var hapticAdvance: TimeInterval { get }
    func setHapticAdvance(_ seconds: TimeInterval)
    func audition(_ event: HapticEvent)
}

struct DeviceButton<Host: DeviceHost>: View {
    let model: Host
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(label)
            }
        }
        .help("Connect phones")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DevicePanel(model: model).frame(width: 288)
        }
    }

    private var count: Int { model.session.readyLinks.count }

    private var label: String {
        switch count {
        case 0: "Connect phone"
        case 1: model.session.readyLinks[0].name
        default: "\(count) phones"
        }
    }

    private var dot: Color {
        if count > 0 { return model.session.previewOn ? Theme.accent : Theme.textSecondary }
        return model.session.listenError == nil ? Theme.ink.opacity(0.25) : Theme.danger
    }
}

private struct DevicePanel<Host: DeviceHost>: View {
    let model: Host

    private var session: DeviceSession { model.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            join
            if !session.readyLinks.isEmpty { devices }
        }
        .font(Theme.font)
        .padding(16)
    }

    // MARK: Join

    private var join: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a phone").fontWeight(.semibold)
            if let err = session.listenError {
                Text(err).foregroundStyle(Theme.danger)
            }
            if !session.joinLink.isEmpty {
                QRImage(text: session.joinLink)
                    .frame(width: 168, height: 168)
                    .padding(8)
                    // QR stays black on white in both modes, or phones cannot read it.
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity)
                Text("Scan with the Feel app, or enter this code. Any number of phones can join.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(session.code.prefix(3) + " " + session.code.suffix(3))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Spacer()
                    Button("New Code") { session.resetCode() }.buttonStyle(QuietButtonStyle())
                }
            } else if session.listenError == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting…").foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Connected

    private var devices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Theme.border.frame(height: 1)
            Text("Connected").fontWeight(.semibold)
            VStack(spacing: 6) {
                ForEach(session.readyLinks) { link in row(link) }
            }
            Toggle(isOn: Binding(get: { session.previewOn }, set: { session.previewOn = $0 })) {
                Text("Live preview").frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch).controlSize(.mini)
            Toggle(isOn: Binding(get: { session.shareVideo }, set: { session.shareVideo = $0 })) {
                Text("Play video on phones").frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch).controlSize(.mini)
            FillSlider(
                label: "Haptic advance",
                value: Binding(get: { model.hapticAdvance * 1000 }, set: { model.setHapticAdvance($0 / 1000) }),
                range: -100...300,
                step: 5,
                format: { "\(Int($0.rounded())) ms" }
            )
            Text("Raise if haptics feel late.").font(Theme.fontSmall).foregroundStyle(Theme.textSecondary)
            HStack {
                Button("Send Test Tap") { model.audition(HapticEvent(type: .tap, start: 0, intensity: 1, sharpness: 0.7)) }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Disconnect All") { session.disconnectAll() }.buttonStyle(QuietButtonStyle())
            }
        }
    }

    private func row(_ link: DeviceLink) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(link.name).fontWeight(.medium)
                if let line = videoLine(link) { Text(line).foregroundStyle(Theme.textSecondary) }
                else if let c = link.status, !c.engineReady { Text(c.message ?? "Haptic engine not ready.").foregroundStyle(Theme.danger) }
            }
            Spacer()
            if let rtt = link.status?.rtt {
                Text("\(Int((rtt * 1000).rounded())) ms").monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            IconButton(symbol: "xmark", label: "Disconnect") { session.disconnect(link) }
        }
    }

    private func videoLine(_ link: DeviceLink) -> String? {
        guard session.shareVideo else { return nil }
        switch link.video {
        case .none, .ready: return nil
        case .preparing: return "Preparing video…"
        case .sending(let p): return "Sending video \(Int(p * 100))%"
        case .failed(let m): return m
        }
    }
}

private struct QRImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
        }
    }

    static func render(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: out.extent.width, height: out.extent.height))
    }
}
