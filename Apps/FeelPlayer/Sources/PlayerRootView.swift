// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AppKit
import FeelCore
import SwiftUI

struct PlayerRootView: View {
    @Bindable var model: PlayerModel
    @State private var isTargeted = false

    var body: some View {
        Group {
            if model.hasVideo {
                VideoScreen(model: model)
            } else {
                Welcome(model: model, isTargeted: isTargeted)
            }
        }
        .font(Theme.font)
        .preferredColorScheme(model.hasVideo ? .dark : nil)
        .navigationTitle(model.title)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await model.open(url) }
            }
            return true
        }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct Welcome: View {
    let model: PlayerModel
    let isTargeted: Bool
    private let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 6) {
                Text("Drop a video").fontWeight(.medium)
                Text("MP4, MOV or M4V. Feel makes haptics from its sound as it opens.")
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Choose Video…", action: model.openPanel)
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .padding(.top, 12)
            }
            .padding(32)
            .frame(maxWidth: 480, maxHeight: 300)
            .background(shape.fill(isTargeted ? Theme.accent.opacity(0.08) : .clear))
            .overlay(shape.stroke(isTargeted ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [] : [5, 4])))
            .animation(Theme.state, value: isTargeted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            DeviceButton(model: model)
                .buttonStyle(QuietButtonStyle())
                .focusable(false)
                .padding(12)
        }
        .foregroundStyle(Theme.textPrimary)
    }
}

/// Only the video, edge to edge. Move the pointer to show the controls. They hide again while it plays.
private struct VideoScreen: View {
    @Bindable var model: PlayerModel
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var shown = true
    @State private var moves = 0
    @State private var overControls = false

    private struct HideTimer: Hashable {
        let moves: Int
        let shown: Bool
        let playing: Bool
        let hold: Bool
    }

    private var visible: Bool {
        shown || !model.video.isPlaying || model.isScrubbing || model.isMaking || voiceOver
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerView(player: model.video.player, cornerRadius: 0).ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.togglePlay() }
                .accessibilityHidden(true)
                .ignoresSafeArea()
            if model.isMaking { preparing.transition(.opacity) }
            controls
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)
        }
        .foregroundStyle(.white)
        .background(WindowButtons(visible: visible))
        .animation(Theme.enter, value: visible)
        .animation(Theme.enter, value: model.isMaking)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                shown = true
                moves += 1
            case .ended:
                shown = false
            }
        }
        .onChange(of: visible) { _, now in
            if !now { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        .task(id: HideTimer(moves: moves, shown: shown, playing: model.video.isPlaying, hold: overControls)) {
            guard shown, model.video.isPlaying, !overControls else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { shown = false }
        }
    }

    private var preparing: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Preparing to play").fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.55))
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.25), .black.opacity(0.25), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if !model.isMaking { centerControls }
            VStack(alignment: .leading, spacing: 4) {
                topBar
                notices
                Spacer()
                if !model.isMaking {
                    bottomBar.onHover { overControls = $0 }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text(model.title).fontWeight(.medium).lineLimit(1)
            Spacer()
            DeviceButton(model: model)
                .buttonStyle(QuietButtonStyle())
                .focusable(false)
            IconButton(symbol: model.audioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       label: model.audioMuted ? "Turn sound on" : "Turn sound off") { model.audioMuted.toggle() }
            menu
        }
        // The window buttons sit at the left end of this row.
        .padding(.leading, 64)
    }

    private var menu: some View {
        Menu {
            Button("Open…", action: model.openPanel)
            Divider()
            if !model.events.isEmpty {
                Button("Test Haptics") { model.audition(HapticEvent(type: .tap, start: 0, intensity: 1, sharpness: 0.8)) }
                    .disabled(model.session.readyLinks.isEmpty)
                Toggle("Mute Haptics", isOn: $model.hapticsMuted)
                Button("Remove Haptics", action: model.clearHaptics)
            } else if !model.isMaking {
                Button("Make Haptics", action: model.makeFromSound)
            }
            Divider()
            Button("Close Video", action: model.close)
        } label: {
            Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }

    @ViewBuilder private var notices: some View {
        if let warning = model.warning { Text(warning).foregroundStyle(Theme.danger) }
        if let message = model.message { Text(message).foregroundStyle(Theme.danger) }
    }

    /// Skip back, play or pause, skip forward.
    private var centerControls: some View {
        HStack(spacing: 48) {
            skip("gobackward.10", label: "Back 10 seconds", by: -10)
            Button(action: model.togglePlay) {
                Image(systemName: model.video.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(0.55), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.playBlocked)
            .help(model.video.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(model.video.isPlaying ? "Pause" : "Play")
            skip("goforward.10", label: "Forward 10 seconds", by: 10)
        }
    }

    private func skip(_ symbol: String, label: String, by seconds: Double) -> some View {
        Button { model.skip(by: seconds) } label: {
            Image(systemName: symbol).font(.system(size: 22)).frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(Timebase.clock(model.video.currentTime)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
            Scrubber(model: model)
            Text(Timebase.clock(model.video.duration)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
            IconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Full screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
    }
}

/// The close, minimize and zoom buttons hide with the other controls.
private struct WindowButtons: NSViewRepresentable {
    let visible: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            view.window?.standardWindowButton(kind)?.animator().alphaValue = visible ? 1 : 0
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            view.window?.standardWindowButton(kind)?.alphaValue = 1
        }
    }
}

private struct Scrubber: View {
    let model: PlayerModel

    var body: some View {
        GeometryReader { geo in
            let duration = max(model.video.duration, 0.01)
            let fraction = min(max(model.video.currentTime / duration, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24)).frame(height: 4)
                Capsule().fill(.white).frame(width: geo.size.width * fraction, height: 4)
                Circle().fill(.white).frame(width: 12, height: 12)
                    .offset(x: geo.size.width * fraction - 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in model.scrub(to: min(max(g.location.x / geo.size.width, 0), 1) * duration) }
                    .onEnded { g in model.endScrub(at: min(max(g.location.x / geo.size.width, 0), 1) * duration) }
            )
            .overlay {
                if !model.hapticGraph.isEmpty {
                    // Stands just over the track and takes no layout space.
                    Color.clear.frame(height: 0).overlay(alignment: .bottom) {
                        HapticGraphView(levels: model.hapticGraph, progress: fraction, accent: Theme.accent)
                            .frame(height: 32)
                    }
                    .offset(y: -5)
                }
            }
        }
        .frame(height: 24)
        .accessibilityLabel("Position")
        .accessibilityValue(Timebase.clock(model.video.currentTime))
    }
}
