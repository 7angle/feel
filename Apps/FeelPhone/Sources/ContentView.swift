// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import FeelCore
import SwiftUI
import UIKit

/// Same rules as the Mac: three grays. Orange is only ever something you feel.
enum Style {
    /// Follows light and dark mode. Text and lines are `ink` at some opacity.
    static let ink = adaptive(light: UIColor(white: 0.07, alpha: 1), dark: .white)
    /// Opposite of `ink`, for text on an `ink` fill.
    static let paper = adaptive(light: .white, dark: UIColor(white: 0.07, alpha: 1))
    static let bg = adaptive(
        light: UIColor(red: 0.955, green: 0.95, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.07, blue: 0.066, alpha: 1)
    )
    static let panel = adaptive(
        light: UIColor(red: 0.995, green: 0.99, blue: 0.985, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.125, blue: 0.12, alpha: 1)
    )
    static let secondary = ink.opacity(0.6)
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.2)
    static let danger = adaptive(
        light: UIColor(red: 0.8, green: 0.13, blue: 0.1, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.4, blue: 0.38, alpha: 1)
    )
    static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct ContentView: View {
    let model: CompanionModel

    var body: some View {
        ZStack {
            Style.bg.ignoresSafeArea()
            switch model.link {
            case .idle, .connecting: SoloView(connect: model)
            case .connected(let name): PreviewView(model: model, editor: name)
            }
        }
        .tint(Style.ink)
        .animation(Style.enter, value: model.link)
    }
}

// MARK: Join

struct JoinView: View {
    let model: CompanionModel
    @State private var scanning = false
    @State private var picked: FeelBrowser.Device?
    @State private var code = ""

    private static let signature = [
        HapticEvent(type: .tap, start: 0, intensity: 1),
        HapticEvent(type: .rumble, start: 0.25, duration: 0.5, intensity: 0.55, fadeIn: 0.2, fadeOut: 0.25),
        HapticEvent(type: .tickTrain, start: 0.85, intensity: 0.8, repetitionInterval: 0.09, repetitionCount: 4),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    HapticBars(events: Self.signature).frame(width: 112, height: 32).padding(.bottom, 10)
                    Text("Connect to a Mac").font(.title2.weight(.semibold))
                    Text("Open Feel Player or Feel Editor on your Mac, click Connect phone, then scan the QR code. The Mac sends its video here and plays haptics in sync.")
                        .foregroundStyle(Style.secondary)
                        .multilineTextAlignment(.center)
                }
                if case .connecting(let name) = model.link {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Connecting to \(name)…").foregroundStyle(Style.secondary)
                    }
                    .frame(minHeight: 52)
                    Button("Cancel", action: model.disconnect).foregroundStyle(Style.secondary).frame(minHeight: 44)
                } else {
                    Button { scanning = true } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder").wideLabel()
                    }
                    .buttonStyle(PressStyle(fill: Style.ink, text: Style.paper))
                    macList
                }
                messages
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .safeAreaInset(edge: .bottom) {
            Text("Both devices must be on the same Wi-Fi.")
                .font(.footnote)
                .foregroundStyle(Style.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .onAppear { model.startBrowsing() }
        .sheet(isPresented: $scanning) {
            ScannerSheet { text in
                scanning = false
                if let join = JoinLink(url: text) { model.connect(join) }
                else { model.reportError("This QR code is not from Feel.") }
            }
        }
    }

    @ViewBuilder private var messages: some View {
        if let e = model.error { Text(e).font(.footnote).foregroundStyle(Style.danger).multilineTextAlignment(.center) }
        if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Style.secondary).multilineTextAlignment(.center) }
        if !model.player.supportsHaptics {
            Label("This device does not support Core Haptics.", systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(Style.danger)
        }
    }

    @ViewBuilder private var macList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.macs.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Macs on this Wi-Fi…").font(.footnote).foregroundStyle(Style.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Or pick a Mac and type its code").font(.footnote).foregroundStyle(Style.secondary)
                VStack(spacing: 0) {
                    ForEach(model.macs) { mac in
                        Button {
                            picked = picked == mac ? nil : mac
                            code = ""
                        } label: {
                            HStack {
                                Image(systemName: "laptopcomputer").foregroundStyle(Style.secondary)
                                Text(mac.name).lineLimit(1)
                                Spacer()
                                if picked == mac { Image(systemName: "checkmark").font(.footnote.weight(.semibold)) }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked == mac ? .isSelected : [])
                    }
                }
                .background(Style.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let picked {
                    CodeField(code: $code).padding(.top, 4)
                    Button { model.connect(to: picked, code: code) } label: {
                        Text("Connect").wideLabel()
                    }
                    .buttonStyle(PressStyle(fill: code.count == 6 ? Style.ink : Style.panel, text: code.count == 6 ? Style.paper : Style.secondary))
                    .disabled(code.count != 6)
                }
            }
        }
    }
}

/// Six boxes over one hidden field, so paste, autofill and VoiceOver work as normal.
private struct CodeField: View {
    @Binding var code: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("Code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.02)
                .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    cell(i)
                    if i == 2 { Spacer().frame(width: 6) }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }

    private func cell(_ i: Int) -> some View {
        let digits = Array(code)
        let current = focused && i == min(digits.count, 5)
        return Text(i < digits.count ? String(digits[i]) : "")
            .font(.title3.weight(.medium).monospacedDigit())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Style.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Style.ink.opacity(current ? 0.7 : 0), lineWidth: 1.5)
            )
    }
}

private enum CameraProblem {
    case denied, unavailable
}

private struct ScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var problem: CameraProblem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            QRScanner(onCode: onCode) { problem = $0 }.ignoresSafeArea()
            if let problem {
                VStack(spacing: 12) {
                    Text(problem == .denied ? "Feel cannot use the camera" : "No camera found").font(.headline)
                    Text(problem == .denied ? "Allow camera access in Settings to scan the code on your Mac. You can also type the code." : "Close this and type the code from your Mac.")
                        .foregroundStyle(Style.secondary)
                        .multilineTextAlignment(.center)
                    if problem == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button { openURL(url) } label: { Text("Open Settings").wideLabel() }
                            .buttonStyle(PressStyle(fill: Style.ink, text: Style.paper))
                            .padding(.top, 8)
                    }
                }
                .padding(32)
            } else {
                VStack(spacing: 20) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 240, height: 240)
                    Text("Point at the QR code on your Mac")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .allowsHitTesting(false)
            }
            VStack {
                HStack {
                    Spacer()
                    RoundIcon(symbol: "xmark", label: "Close") { dismiss() }
                }
                Spacer()
            }
            .padding(12)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Camera that reads one QR code.
private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onProblem: (CameraProblem) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onCode = onCode
        c.onProblem = onProblem
        return c
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        var onProblem: ((CameraProblem) -> Void)?
        private let session = AVCaptureSession()
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    if ok { self.configure() } else { self.onProblem?(.denied) }
                }
            }
        }

        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                onProblem?(.unavailable)
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.first { $0 is AVCaptureVideoPreviewLayer }?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { if s.isRunning { s.stopRunning() } }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            done = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode?(text)
        }
    }
}

// MARK: Connected

struct PreviewView: View {
    let model: CompanionModel
    let editor: String
    @Environment(\.verticalSizeClass) private var vSize

    private var videoReady: Bool {
        if case .ready = model.video.state, model.video.player != nil { return true } else { return false }
    }

    var body: some View {
        // Landscape with a video: the video fills the screen. Otherwise the normal page.
        if vSize == .compact, videoReady, let player = model.video.player {
            VideoScreen(model: model, player: player) { fullscreenTopBar }
        } else {
            GeometryReader { geo in
                ScrollView {
                    page.frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var page: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                StatusDot(ready: model.engineReady)
                Text(editor).font(.headline).lineLimit(1)
                if let rtt = model.rtt {
                    Text("\(Int((rtt * 1000).rounded())) ms").font(.footnote.monospacedDigit()).foregroundStyle(Style.secondary)
                }
                Spacer()
                RoundIcon(symbol: "xmark", label: "Disconnect", action: model.disconnect)
            }
            videoArea
            if model.duration > 0 { TransportBar(model: model) }
            FeelMeter(model: model).frame(maxHeight: .infinity)
            if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Style.danger).multilineTextAlignment(.center) }
            #if DEBUG
            if !model.debugLine.isEmpty {
                Text(model.debugLine).font(.caption2.monospaced()).foregroundStyle(Style.secondary).multilineTextAlignment(.center)
            }
            #endif
            Button(action: model.testHaptic) {
                Text("Test Haptic").wideLabel()
            }
            .buttonStyle(PressStyle(fill: Style.panel, text: Style.ink))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var fullscreenTopBar: some View {
        HStack(spacing: 8) {
            StatusDot(ready: model.engineReady)
            Text(editor).font(.footnote.weight(.medium)).lineLimit(1)
            if let n = model.notice { Text(n).font(.footnote).foregroundStyle(Style.danger).lineLimit(1) }
            Spacer()
            SoundButton(video: model.video)
            RoundIcon(symbol: "xmark", label: "Disconnect", action: model.disconnect)
        }
    }

    @ViewBuilder private var videoArea: some View {
        switch model.video.state {
        case .ready:
            if let player = model.video.player {
                ZStack(alignment: .bottomTrailing) {
                    PlayerSurface(player: player)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    SoundButton(video: model.video).padding(6).environment(\.colorScheme, .dark)
                }
            }
        case .receiving(let p):
            VStack(spacing: 12) {
                Text("Getting video from Mac").font(.subheadline)
                ProgressView(value: p).frame(maxWidth: 200)
                Text("\(Int(p * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(Style.secondary)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Style.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .failed(let msg):
            Text(msg).font(.footnote).foregroundStyle(Style.danger)
        case .none:
            EmptyView()
        }
    }
}

/// Time, with a glow that hits as hard as the haptic does. Own view: it reads time on every update.
private struct FeelMeter: View {
    let model: CompanionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let level = model.hapticLevel
        VStack(spacing: 6) {
            Text(Timebase.format(model.mediaTime))
                .font(.system(size: 44, weight: .medium).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(model.eventCount == 1 ? "1 haptic" : "\(model.eventCount) haptics")
                .font(.footnote)
                .foregroundStyle(Style.secondary)
        }
        .frame(minHeight: 150)
        .frame(maxWidth: .infinity)
        .background {
            Circle()
                .fill(Style.accent)
                .frame(width: 200, height: 200)
                .blur(radius: 44)
                .scaleEffect(reduceMotion ? 1 : 0.75 + 0.5 * level)
                .opacity(level * 0.7)
                .accessibilityHidden(true)
        }
    }
}

private struct StatusDot: View {
    let ready: Bool

    var body: some View {
        Circle()
            .fill(ready ? Style.accent : Style.danger)
            .frame(width: 8, height: 8)
            .accessibilityLabel(ready ? "Haptics ready" : "Haptics not ready")
    }
}

/// What the video controls need from a model.
@MainActor protocol PlayerTransport: AnyObject {
    var isPlaying: Bool { get }
    var mediaTime: TimelineTime { get }
    var duration: TimelineTime { get }
    var hapticGraph: [Double] { get }
    func togglePlay()
    func seek(to t: TimelineTime, final: Bool)
}

extension CompanionModel: PlayerTransport {}
extension SoloModel: PlayerTransport {}

/// Only the video, edge to edge. Tap to show the controls. They hide again while it plays.
struct VideoScreen<Model: PlayerTransport, Top: View>: View {
    let model: Model
    let player: AVPlayer
    var isPreparing = false
    @ViewBuilder let top: () -> Top

    private struct HideTimer: Hashable {
        let shown: Bool
        let playing: Bool
        let scrubbing: Bool
        let skips: Int
    }

    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var shown = true
    @State private var scrubbing = false
    @State private var skips = 0

    private var visible: Bool { shown || !model.isPlaying || scrubbing || isPreparing || voiceOver }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: player).ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { shown = model.isPlaying ? !shown : true }
                .accessibilityHidden(true)
            if isPreparing { preparing.transition(.opacity) }
            controls
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2), value: visible)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2), value: isPreparing)
        .statusBarHidden(vSize == .compact || !visible)
        .persistentSystemOverlays(visible ? .automatic : .hidden)
        .task(id: HideTimer(shown: shown, playing: model.isPlaying, scrubbing: scrubbing, skips: skips)) {
            guard shown, model.isPlaying, !scrubbing else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { shown = false }
        }
    }

    private var preparing: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Preparing to play").font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.55))
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.25), .black.opacity(0.25), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if !isPreparing { centerControls }
            VStack {
                top()
                Spacer()
                if !isPreparing {
                    PositionSlider(model: model, showTime: true) { scrubbing = $0 }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Skip back, play or pause, skip forward.
    private var centerControls: some View {
        HStack(spacing: 48) {
            skip("gobackward.10", label: "Back 10 seconds", by: -10)
            Button(action: model.togglePlay) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34)).frame(width: 72, height: 72)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(PressStyle(fill: .clear, text: .white))
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            skip("goforward.10", label: "Forward 10 seconds", by: 10)
        }
    }

    private func skip(_ symbol: String, label: String, by seconds: Double) -> some View {
        Button {
            skips += 1
            model.seek(to: min(max(model.mediaTime + seconds, 0), model.duration), final: true)
        } label: {
            Image(systemName: symbol).font(.title2).frame(width: 56, height: 56).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(fill: .clear, text: .white))
        .accessibilityLabel(label)
    }
}

/// 32 pt circle in a 44 pt touch target.
struct RoundIcon: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Style.ink.opacity(0.12), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(fill: .clear, text: Style.ink))
        .accessibilityLabel(label)
    }
}

private struct SoundButton: View {
    let video: CompanionVideo

    var body: some View {
        RoundIcon(
            symbol: video.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
            label: video.soundOn ? "Turn sound off" : "Turn sound on"
        ) { video.soundOn.toggle() }
    }
}

private struct TransportBar: View {
    let model: CompanionModel

    private var isReceiving: Bool {
        if case .receiving = model.video.state { return true } else { return false }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: model.togglePlay) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3).frame(width: 48, height: 48)
                    .background(Style.ink, in: Circle())
            }
            .buttonStyle(PressStyle(fill: .clear, text: Style.paper))
            .disabled(isReceiving)
            .opacity(isReceiving ? 0.4 : 1)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            PositionSlider(model: model, showTime: false)
        }
    }
}

private struct PositionSlider<Model: PlayerTransport>: View {
    let model: Model
    let showTime: Bool
    var onScrub: (Bool) -> Void = { _ in }
    @State private var dragging = false
    @State private var dragValue = 0.0
    @State private var lastSent = Date.distantPast

    var body: some View {
        HStack(spacing: 12) {
            if showTime {
                Text(Timebase.clock(dragging ? dragValue : model.mediaTime))
                    .font(.footnote.monospacedDigit()).foregroundStyle(Style.secondary)
            }
            Slider(
                value: Binding(get: { dragging ? dragValue : model.mediaTime }, set: { dragValue = $0 }),
                in: 0...max(model.duration, 0.1)
            ) {
                Text("Position")
            } onEditingChanged: { editing in
                if editing {
                    dragValue = model.mediaTime
                    dragging = true
                } else {
                    model.seek(to: dragValue, final: true)
                    dragging = false
                }
                onScrub(editing)
            }
            .tint(Style.ink)
            .overlay {
                if showTime, !model.hapticGraph.isEmpty {
                    // Stands just over the track and takes no layout space.
                    Color.clear.frame(height: 0).overlay(alignment: .bottom) {
                        HapticGraphView(
                            levels: model.hapticGraph,
                            progress: (dragging ? dragValue : model.mediaTime) / max(model.duration, 0.1),
                            accent: Style.accent
                        )
                        .frame(height: 28)
                        .padding(.horizontal, 14) // The thumb stops this far from each end of the track.
                    }
                    .offset(y: -5)
                }
            }
            .accessibilityValue(Timebase.clock(model.mediaTime))
            .onChange(of: dragValue) { _, v in
                guard dragging, Date().timeIntervalSince(lastSent) > 0.06 else { return }
                lastSent = Date()
                model.seek(to: v, final: false)
            }
            if showTime {
                Text(Timebase.clock(model.duration)).font(.footnote.monospacedDigit()).foregroundStyle(Style.secondary)
            }
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class View: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> View {
        let v = View()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ v: View, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

/// What events feel like over time, drawn as bars.
private struct HapticBars: View {
    let events: [HapticEvent]

    var body: some View {
        Canvas { ctx, size in
            let span = max(events.map(\.end).max() ?? 0, 0.3) + 0.08
            var bars = Path()
            var x: CGFloat = 0
            while x < size.width {
                let level = CGFloat(events.level(at: Double(x / size.width) * span))
                if level > 0.02 {
                    let h = max(level * size.height, 2)
                    bars.addRoundedRect(in: CGRect(x: x, y: (size.height - h) / 2, width: 2, height: h), cornerSize: CGSize(width: 1, height: 1))
                }
                x += 3
            }
            ctx.fill(bars, with: .color(Style.accent))
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Full-width label at a comfortable touch height.
    func wideLabel() -> some View {
        frame(maxWidth: .infinity).frame(minHeight: 52)
    }
}

struct PressStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(text)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Style.press, value: configuration.isPressed)
    }
}
