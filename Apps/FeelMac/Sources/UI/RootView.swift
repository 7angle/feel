// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false
    @AppStorage("layout.timeline") private var timelineH = 280.0

    var body: some View {
        VStack(spacing: 0) {
            StageView(model: model, isTargeted: isTargeted)
            if !model.isWelcome {
                Splitter(axis: .horizontal, size: $timelineH, range: 220...700, invert: true)
                TimelineView(model: model)
                    .frame(height: timelineH)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.enter, value: model.isWelcome)
        .font(Theme.font)
        .foregroundStyle(Theme.textPrimary)
        .background { AmbientBackdrop(model: model).ignoresSafeArea() }
        .navigationTitle(model.windowTitle)
        .toolbar { WindowToolbar(model: model) }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .task { model.offerRecovery() }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.pathExtension.lowercased() == ProjectStore.fileExtension {
                        await model.openProject(at: url)
                    } else {
                        await model.importVideo(url)
                    }
                }
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

struct WindowToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo).help("Undo (⌘Z)")
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!model.canRedo).help("Redo (⇧⌘Z)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.importVideoPanel() } label: { Label("Import Video", systemImage: "film") }
                .help("Import video (⌘I)")
        }
        // Not focusable: Space must always mean play, never "press this button".
        ToolbarItem(placement: .primaryAction) { DeviceButton(model: model).focusable(false) }
        ToolbarItem(placement: .primaryAction) { ExportButton(model: model).focusable(false) }
    }
}

/// The picture, with panels floating over it. Panels never move the video.
struct StageView: View {
    let model: AppModel
    let isTargeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSelection: Bool { !model.selection.isEmpty }

    var body: some View {
        ZStack {
            Screen(model: model, isTargeted: isTargeted)
                .padding(.horizontal, model.isWelcome ? 16 : 64)
                .padding(.vertical, 12)
            if !model.isWelcome {
                HStack(alignment: .top, spacing: 8) {
                    rail
                    if let panel = model.stagePanel {
                        StagePanelCard(model: model, panel: panel)
                            .transition(cardTransition(anchor: .leading, dx: -8))
                    }
                    Spacer(minLength: 0)
                    if hasSelection {
                        InspectorView(model: model)
                            .transition(cardTransition(anchor: .trailing, dx: 8))
                    }
                }
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(Theme.enter, value: hasSelection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rail: some View {
        VStack(spacing: 2) {
            ForEach(StagePanel.allCases, id: \.self) { p in
                IconButton(symbol: p.symbol, label: p.title, active: model.stagePanel == p, size: 32) {
                    withAnimation(Theme.enter) { model.toggle(p) }
                }
            }
        }
        .padding(4)
        .floating(radius: 12)
    }

    private func cardTransition(anchor: UnitPoint, dx: CGFloat) -> AnyTransition {
        if reduceMotion { return .opacity }
        let moved = AnyTransition.opacity
            .combined(with: .scale(scale: 0.98, anchor: anchor))
            .combined(with: .offset(x: dx))
        return .asymmetric(insertion: moved.animation(Theme.enter), removal: moved.animation(Theme.exit))
    }
}

private struct Screen: View {
    let model: AppModel
    let isTargeted: Bool

    var body: some View {
        switch model.videoState {
        case .loaded:
            VideoFrame(model: model)
        case .none:
            EmptyState(title: "Drop a video", detail: "MP4, MOV or M4V", action: ("Choose Video…", model.importVideoPanel), isTargeted: isTargeted)
        case .missing(let url):
            EmptyState(title: "Video not found", detail: url.lastPathComponent, action: ("Relink Video…", model.relinkVideoPanel), isTargeted: isTargeted)
        case .failed(let msg):
            EmptyState(title: "Cannot open video", detail: msg, action: ("Choose Another Video…", model.importVideoPanel), isTargeted: isTargeted)
        }
    }
}

/// Fits the picture exactly, so no black bars. Click to play or pause.
private struct VideoFrame: View {
    let model: AppModel

    private var aspect: CGFloat {
        guard let m = model.project.video?.metadata, m.width > 0, m.height > 0 else { return 16 / 9 }
        return CGFloat(m.width) / CGFloat(m.height)
    }

    var body: some View {
        ZStack {
            FeelGlow(model: model)
            PlayerView(player: model.video.player)
            RoundedRectangle(cornerRadius: PlayerNSView.cornerRadius, style: .continuous)
                .stroke(Theme.border)
                .contentShape(Rectangle())
                .onTapGesture { model.togglePlay() }
                .accessibilityLabel("Video preview")
                .accessibilityAddTraits(.isButton)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The picture glows as hard as the haptic under the playhead hits. Own view: it reads time on every frame.
private struct FeelGlow: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let level = reduceMotion || model.hapticsMuted ? 0 : model.project.events.level(at: model.video.currentTime)
        RoundedRectangle(cornerRadius: PlayerNSView.cornerRadius, style: .continuous)
            .fill(Theme.accent)
            .blur(radius: 28)
            .opacity(level * 0.75)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Blurred current frame behind everything, so the room takes the color of the film.
private struct AmbientBackdrop: View {
    let model: AppModel
    /// Change at most every few seconds. Fast cuts must not flicker the whole window.
    private let framesPerChange = 4
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strip = model.thumbs.strip
        let index = Int(model.video.currentTime / max(strip.spacing, 0.01)) / framesPerChange * framesPerChange
        ZStack {
            Theme.bg
            if let image = strip.images[index] {
                Color.clear
                    .overlay {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 70)
                            .opacity(scheme == .dark ? 0.3 : 0.22)
                    }
                    .clipped()
                    .id(index)
                    .transition(.opacity)
            }
        }
        .animation(.linear(duration: 0.9), value: index)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let action: (String, () -> Void)
    var isTargeted = false

    private let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
    private let signature = [
        HapticEvent(type: .tap, start: 0, intensity: 1),
        HapticEvent(type: .rumble, start: 0.25, duration: 0.5, intensity: 0.55, fadeIn: 0.2, fadeOut: 0.25),
        HapticEvent(type: .tickTrain, start: 0.85, intensity: 0.8, repetitionInterval: 0.09, repetitionCount: 4),
    ]

    var body: some View {
        VStack(spacing: 6) {
            HapticSignature(events: signature, opacity: 1)
                .frame(width: 96, height: 28)
                .padding(.bottom, 12)
            Text(title).fontWeight(.medium)
            Text(detail).foregroundStyle(Theme.textSecondary).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
            Button(action.0, action: action.1)
                .buttonStyle(QuietButtonStyle(prominent: true))
                .padding(.top, 12)
        }
        .padding(32)
        .frame(maxWidth: 560, maxHeight: 340)
        .background(shape.fill(isTargeted ? Theme.accent.opacity(0.08) : .clear))
        .overlay(
            shape.stroke(isTargeted ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [] : [5, 4]))
        )
        .scaleEffect(isTargeted ? 1.01 : 1)
        .animation(Theme.state, value: isTargeted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What events feel like over time, drawn as bars.
struct HapticSignature: View {
    let events: [HapticEvent]
    var opacity = 0.8

    var body: some View {
        Canvas { ctx, size in
            let span = max(events.map(\.end).max() ?? 0, 0.3) + 0.08
            let step: CGFloat = 3
            var bars = Path()
            var x: CGFloat = 0
            while x < size.width {
                let t = Double(x / size.width) * span
                let level = CGFloat(events.level(at: t))
                if level > 0.02 {
                    let h = max(level * size.height, 2)
                    bars.addRoundedRect(in: CGRect(x: x, y: (size.height - h) / 2, width: 2, height: h), cornerSize: CGSize(width: 1, height: 1))
                }
                x += step
            }
            ctx.fill(bars, with: .color(Theme.accent.opacity(opacity)))
        }
        .accessibilityHidden(true)
    }
}
