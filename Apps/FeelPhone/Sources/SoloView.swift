// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import SwiftUI
import UniformTypeIdentifiers

/// Home of the app: a video player that makes you feel the video.
/// Connecting to a Mac is an option, not the start.
struct SoloView: View {
    let connect: CompanionModel
    @Environment(\.scenePhase) private var phase
    @State private var model = SoloModel()
    @State private var picking = false
    @State private var connecting = false
    @State private var about = false

    var body: some View {
        ZStack {
            Style.bg.ignoresSafeArea()
            if let player = model.player {
                VideoScreen(model: model, player: player, isPreparing: model.isMaking) {
                    VStack(alignment: .leading, spacing: 4) {
                        topBar
                        notices
                    }
                }
            } else {
                VStack(spacing: 16) {
                    HStack {
                        Text("Feel").font(.headline)
                        Spacer()
                        connectingStatus
                        menu
                    }
                    empty
                    notices
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .tint(Style.ink)
        .preferredColorScheme(model.hasVideo ? .dark : nil)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .json]) { result in
            switch result {
            case .success(let url): Task { await model.open(url) }
            case .failure: model.message = "Cannot open that file."
            }
        }
        .sheet(isPresented: $connecting) {
            JoinView(model: connect)
                .background(Style.bg)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $about) { AboutView() }
        .onChange(of: connect.link) { _, link in
            // The Mac takes over once it is connected.
            if case .connected = link { model.pause() }
        }
        .onChange(of: phase) { _, new in
            // No sound and no haptics from an app the user left.
            if new == .background { model.pause() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Text(model.name).font(.footnote.weight(.medium)).lineLimit(1)
            Spacer()
            connectingStatus
            RoundIcon(
                symbol: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: model.soundOn ? "Turn sound off" : "Turn sound on"
            ) { model.soundOn.toggle() }
            menu
        }
    }

    @ViewBuilder private var connectingStatus: some View {
        if case .connecting(let mac) = connect.link {
            Button { connecting = true } label: {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(mac).lineLimit(1) }
                    .font(.footnote).foregroundStyle(Style.secondary)
            }
        }
    }

    private var menu: some View {
        Menu {
            Button {
                // No sound or haptics behind the file picker, or while the next video loads.
                model.pause()
                picking = true
            } label: { Label("Open Video…", systemImage: "film") }
            Button {
                model.pause()
                connecting = true
            } label: { Label("Connect to Mac…", systemImage: "desktopcomputer") }
            Button { about = true } label: { Label("About", systemImage: "info.circle") }
            if model.hasVideo {
                if !model.events.isEmpty {
                    Button(action: model.testHaptic) { Label("Test Haptics", systemImage: "iphone.radiowaves.left.and.right") }
                    Button(action: model.clearHaptics) { Label("Remove Haptics", systemImage: "iphone.slash") }
                } else if !model.isMaking {
                    Button(action: model.makeFromSound) { Label("Make Haptics", systemImage: "waveform") }
                }
                Button(role: .destructive) { model.close() } label: { Label("Close Video", systemImage: "xmark") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Style.ink.opacity(0.12), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    // MARK: Empty

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "play.rectangle").font(.system(size: 40, weight: .light)).foregroundStyle(Style.secondary).padding(.bottom, 6)
            Text("Feel your videos").font(.title2.weight(.semibold))
            Text("Open a video. Feel makes haptics from its sound as it opens, or plays a haptics file from the Feel editor.")
                .foregroundStyle(Style.secondary).multilineTextAlignment(.center)
            Button { picking = true } label: { Label("Open Video", systemImage: "film").wideLabel() }
                .buttonStyle(PressStyle(fill: Style.ink, text: Style.paper))
                .padding(.top, 14)
            Button { connecting = true } label: { Text("Connect to Mac").foregroundStyle(Style.secondary).frame(minHeight: 44) }
            Spacer()
        }
        .frame(maxWidth: 480)
    }

    // MARK: Notices

    @ViewBuilder private var notices: some View {
        if let w = model.warning { Text(w).font(.footnote).foregroundStyle(Style.danger) }
        if let m = model.message { Text(m).font(.footnote).foregroundStyle(Style.danger) }
        if !model.haptics.supportsHaptics {
            Label("This device does not support Core Haptics.", systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(Style.danger)
        }
    }
}
