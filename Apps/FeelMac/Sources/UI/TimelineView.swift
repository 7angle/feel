// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import AppKit
import SwiftUI

enum LaneGeometry {
    static func rect(_ e: HapticEvent, zoom: Double, height: CGFloat) -> CGRect {
        let h = max((height - 8) * e.intensity, 6)
        return CGRect(x: e.start * zoom, y: height - 4 - h, width: max(e.effectiveDuration * zoom, 4), height: h)
    }
}

private enum DragMode {
    case scrub
    case move(anchor: UUID)
    case resize(UUID, EventEditing.ResizeEdge)
}

struct TimelineView: View {
    @Bindable var model: AppModel
    @State private var drag: DragMode?
    @State private var dropTargeted = false

    private let rulerH: CGFloat = 22
    private let videoH: CGFloat = 52
    private let audioH: CGFloat = 36
    private let gap: CGFloat = 3
    private let inset: CGFloat = 5
    private var laneTop: CGFloat { rulerH + videoH + audioH + gap * 3 }

    @AppStorage("timeline.follow") private var follow = true
    @State private var scrollX: CGFloat = 0
    @State private var followX: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            controls
            GeometryReader { outer in
                // Haptics take all room left over. They are the point of the app.
                let lane = max(44, outer.size.height - laneTop - 10)
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: true) {
                            track(viewport: geo.size.width - inset * 2, lane: lane)
                                .padding(.horizontal, inset)
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: ScrollXKey.self, value: -g.frame(in: .named("tl")).minX)
                                })
                                .overlay(alignment: .topLeading) {
                                    // Real layout space. scrollTo reads the frame, not a visual offset.
                                    HStack(spacing: 0) {
                                        Color.clear.frame(width: followX, height: 1)
                                        Color.clear.frame(width: 1, height: 1).id("follow")
                                    }
                                    .allowsHitTesting(false)
                                }
                        }
                        .coordinateSpace(name: "tl")
                        .onPreferenceChange(ScrollXKey.self) { scrollX = $0 }
                        .background {
                            PlayheadFollower(video: model.video, enabled: follow, zoom: model.zoom, viewport: geo.size.width, scrollX: { scrollX }) { x in
                                followX = x
                                DispatchQueue.main.async { proxy.scrollTo("follow", anchor: .leading) }
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) { emptyHint(lane: lane) }
                }
                .padding(.horizontal, inset)
            }
        }
        .deckSurface()
    }

    @ViewBuilder private func emptyHint(lane: CGFloat) -> some View {
        if model.project.events.isEmpty && model.visibleSuggestions.isEmpty {
            Text("No haptics yet. Press ⌘1 to add a tap, or use Auto Haptics.")
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .padding(.leading, 17)
                .frame(height: lane)
                .offset(y: laneTop)
                .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 2) {
                TimeReadout(video: model.video, duration: model.project.duration)
                if model.playBlocked {
                    let p = Int((model.session.videoProgress ?? 0) * 100)
                    Text(p > 0 ? "Sending video \(p)%" : "Preparing video…")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 12)
                }
                Spacer()
                Button { model.autoHaptics() } label: {
                    Label(model.isAutoRunning ? "Analyzing \(Int(model.autoProgress * 100))%" : "Auto Haptics", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(!model.canAutoHaptics)
                .help("Add haptics where the audio and the picture have strong moments")
                IconButton(symbol: "trash", label: "Delete selected haptics (⌫)") { model.deleteSelection() }
                    .disabled(model.selection.isEmpty)
                Divider().frame(height: 14).padding(.horizontal, 6)
                IconButton(
                    symbol: model.audioMuted ? "speaker.slash" : "speaker.wave.2",
                    label: model.audioMuted ? "Unmute audio" : "Mute audio"
                ) { model.audioMuted.toggle() }
                IconButton(
                    symbol: model.hapticsMuted ? "iphone.slash" : "iphone.radiowaves.left.and.right",
                    label: model.hapticsMuted ? "Unmute haptic preview" : "Mute haptic preview"
                ) { model.hapticsMuted.toggle() }
                IconButton(
                    symbol: "scope",
                    label: follow ? "Timeline follows playhead. Click to stop." : "Make timeline follow playhead",
                    active: follow
                ) { follow.toggle() }
                Divider().frame(height: 14).padding(.horizontal, 6)
                IconButton(symbol: "minus", label: "Zoom out (⌘-)") { model.zoom /= 1.25 }
                Slider(value: Binding(get: { log(model.zoom) }, set: { model.zoom = exp($0) }), in: log(10)...log(800)) {
                    Text("Zoom")
                }
                .labelsHidden()
                .frame(width: 88)
                .controlSize(.mini)
                .tint(Theme.textSecondary)
                IconButton(symbol: "plus", label: "Zoom in (⌘=)") { model.zoom *= 1.25 }
            }
            Button { model.togglePlay() } label: {
                Image(systemName: model.video.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.identity)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(PlayButtonStyle())
            .disabled(model.videoState != .loaded || (model.playBlocked && !model.video.isPlaying))
            .help("Play / Pause (Space)")
            .accessibilityLabel(model.video.isPlaying ? "Pause" : "Play")
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }

    private func track(viewport: CGFloat, lane: CGFloat) -> some View {
        let zoom = model.zoom
        let duration = model.project.duration
        let width = max(duration * zoom, viewport)
        let media = duration > 0 ? duration * zoom : viewport
        let height = laneTop + lane
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: gap) {
                RulerCanvas(zoom: zoom, duration: duration).frame(width: media, height: rulerH)
                VideoStrip(strip: model.thumbs.strip, zoom: zoom, duration: duration)
                    .frame(width: media, height: videoH)
                WaveformLane(peaks: model.waveform.peaks, state: model.waveform.state, zoom: zoom, muted: model.audioMuted)
                    .frame(width: media, height: audioH)
                HapticLane(events: model.project.events, ghosts: model.visibleSuggestions.flatMap(\.events), selection: model.selection, zoom: zoom)
                    .frame(width: media, height: lane)
            }
            if dropTargeted {
                RoundedRectangle(cornerRadius: laneRadius, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: laneRadius, style: .continuous).stroke(Theme.accent.opacity(0.7)))
                    .frame(width: media, height: lane)
                    .offset(y: laneTop)
                    .allowsHitTesting(false)
            }
            Playhead(video: model.video, zoom: zoom, height: height)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, location in
            guard let item = items.first else { return false }
            return model.dropLibraryItem(item, at: max(location.x / zoom, 0))
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Delete Selected") { model.deleteSelection() }.disabled(model.selection.isEmpty)
            Button("Select All Haptics") { model.selectAll() }.disabled(model.project.events.isEmpty)
            Divider()
            Button("Delete All Haptics") { model.deleteAllEvents() }.disabled(model.project.events.isEmpty)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if drag == nil { drag = begin(at: v.startLocation, zoom: zoom, lane: lane) }
                    switch drag {
                    case .move(let anchor): model.updateMove(delta: (v.location.x - v.startLocation.x) / zoom, anchor: anchor)
                    case .resize(let id, let edge): model.resize(id, edge: edge, to: v.location.x / zoom)
                    case .scrub, nil: model.scrub(to: v.location.x / zoom)
                    }
                }
                .onEnded { v in
                    switch drag {
                    case .move: model.endMove()
                    case .resize: break
                    case .scrub, nil: model.endScrub(at: v.location.x / zoom)
                    }
                    drag = nil
                }
        )
    }

    /// Decide what a press does: grab/resize an event or scrub.
    private func begin(at p: CGPoint, zoom: Double, lane: CGFloat) -> DragMode {
        guard p.y >= laneTop else { return .scrub }
        let local = CGPoint(x: p.x, y: p.y - laneTop)
        let extend = NSEvent.modifierFlags.contains(.shift)
        if let hit = model.project.events.last(where: { LaneGeometry.rect($0, zoom: zoom, height: lane).insetBy(dx: -4, dy: -6).contains(local) }) {
            let r = LaneGeometry.rect(hit, zoom: zoom, height: lane)
            let grab = min(8, max(r.width / 3, 3))
            let canResizeEnd = hit.type == .rumble || hit.type == .tickTrain
            if !extend, canResizeEnd, abs(local.x - r.maxX) <= grab || (hit.type == .rumble && abs(local.x - r.minX) <= grab) {
                let edge: EventEditing.ResizeEdge = abs(local.x - r.maxX) <= abs(local.x - r.minX) || hit.type == .tickTrain ? .end : .start
                model.select(hit.id, extend: false)
                return .resize(hit.id, edge)
            }
            model.select(hit.id, extend: extend)
            model.beginMove()
            return .move(anchor: hit.id)
        }
        if !extend { model.clearSelection() }
        return .scrub
    }
}

private struct ScrollXKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct PlayButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.paper)
            .background(Circle().fill(Theme.ink.opacity(hovering ? 1 : 0.88)))
            .opacity(enabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(Theme.press, value: configuration.isPressed)
            .animation(Theme.state, value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Circle())
    }
}

/// Own views below read time on every frame, so the rest of the timeline stays still during playback.
private struct TimeReadout: View {
    let video: VideoEngine
    let duration: TimelineTime

    var body: some View {
        HStack(spacing: 8) {
            Text(Timebase.format(video.currentTime)).fontWeight(.medium)
            Text(Timebase.format(duration)).foregroundStyle(Theme.textSecondary)
        }
        .monospacedDigit()
    }
}

private struct Playhead: View {
    let video: VideoEngine
    let zoom: Double
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().frame(width: 1.5, height: height)
            Capsule().frame(width: 9, height: 16).offset(y: 2)
        }
        .foregroundStyle(Theme.ink)
        .shadow(color: Theme.paper.opacity(0.6), radius: 2)
        .frame(width: 9, height: height, alignment: .top)
        .offset(x: video.currentTime * zoom - 4.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PlayheadFollower: View {
    let video: VideoEngine
    let enabled: Bool
    let zoom: Double
    let viewport: CGFloat
    let scrollX: () -> CGFloat
    let scroll: (CGFloat) -> Void

    var body: some View {
        Color.clear.onChange(of: video.currentTime) { _, t in
            guard enabled else { return }
            let x = t * zoom
            let left = scrollX()
            guard x > left + viewport * 0.9 || x < left else { return }
            scroll(max(x - viewport * 0.1, 0))
        }
    }
}

private let laneRadius: CGFloat = 8

private extension GraphicsContext {
    /// Canvas clip, not clipShape. A clipShape would make an offscreen layer as wide as the whole film.
    mutating func clipToLane(_ size: CGSize) {
        clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: laneRadius, style: .continuous))
    }
}

struct RulerCanvas: View {
    let zoom: Double
    let duration: TimelineTime

    private static let steps: [Double] = [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]

    var body: some View {
        Canvas { ctx, size in
            let step = Self.steps.first { $0 * zoom >= 80 } ?? 600
            let minor = step / 4
            var t = 0.0
            let end = Double(size.width) / zoom
            while t <= end {
                let x = t * zoom
                let isMajor = abs(t / step - (t / step).rounded()) < 0.001
                if isMajor {
                    let label = Text(Self.label(t, step: step)).font(Theme.fontSmall).foregroundStyle(Theme.textSecondary)
                    ctx.draw(label, at: CGPoint(x: x + 8, y: size.height / 2), anchor: .leading)
                } else {
                    let dot = CGRect(x: x - 1, y: size.height / 2 - 1, width: 2, height: 2)
                    ctx.fill(Path(ellipseIn: dot), with: .color(Theme.ink.opacity(0.14)))
                }
                t += minor
            }
        }
    }

    static func label(_ t: Double, step: Double) -> String {
        let m = Int(t) / 60
        let s = t - Double(m * 60)
        return step < 1 ? String(format: "%d:%05.2f", m, s) : String(format: "%d:%02d", m, Int(s.rounded()))
    }
}

struct WaveformLane: View {
    let peaks: [Float]
    let state: WaveformStore.State
    let zoom: Double
    let muted: Bool

    var body: some View {
        Canvas { ctx, size in
            ctx.clipToLane(size)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink.opacity(0.04)))
            let mid = size.height / 2
            switch state {
            case .ready:
                let perPx = WaveformStore.bucketsPerSecond / zoom
                let pitch = 3.0
                var path = Path()
                var x = 0.0
                while x < size.width {
                    let lo = Int(x * perPx), hi = min(Int((x + pitch) * perPx), peaks.count - 1)
                    guard lo < peaks.count else { break }
                    var m: Float = 0
                    for i in lo...max(lo, hi) { m = max(m, peaks[i]) }
                    let h = max(CGFloat(min(m, 1)) * (mid - 4), 0.5)
                    path.addRect(CGRect(x: x, y: mid - h, width: 2, height: h * 2))
                    x += pitch
                }
                ctx.fill(path, with: .color(Theme.ink.opacity(muted ? 0.12 : 0.34)))
            case .loading:
                ctx.draw(Text("Reading audio…").font(Theme.fontSmall).foregroundStyle(Theme.textSecondary), at: CGPoint(x: 12, y: mid), anchor: .leading)
            case .noAudio:
                ctx.draw(Text("No audio").font(Theme.fontSmall).foregroundStyle(Theme.textSecondary), at: CGPoint(x: 12, y: mid), anchor: .leading)
            case .idle:
                break
            }
        }
    }
}

struct VideoStrip: View {
    let strip: ThumbnailStore.Strip
    let zoom: Double
    let duration: TimelineTime

    var body: some View {
        Canvas { ctx, size in
            ctx.clipToLane(size)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink.opacity(0.04)))
            guard duration > 0 else { return }
            let tileW = strip.spacing * zoom
            for (idx, image) in strip.images {
                let rect = CGRect(x: Double(idx) * tileW, y: 0, width: tileW, height: size.height)
                guard rect.maxX >= 0, rect.minX <= size.width else { continue }
                ctx.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    let aspect = CGFloat(image.width) / CGFloat(image.height)
                    let drawW = max(rect.height * aspect, tileW)
                    let drawRect = CGRect(x: rect.midX - drawW / 2, y: rect.minY, width: drawW, height: rect.height)
                    layer.draw(Image(decorative: image, scale: 1), in: drawRect)
                }
            }
        }
    }
}

struct HapticLane: View {
    let events: [HapticEvent]
    var ghosts: [HapticEvent] = []
    let selection: Set<UUID>
    let zoom: Double

    var body: some View {
        Canvas { ctx, size in
            ctx.clipToLane(size)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink.opacity(0.04)))
            for g in ghosts {
                let r = LaneGeometry.rect(g, zoom: zoom, height: size.height)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(Theme.accent.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            let base = size.height - 4
            let full = size.height - 8
            for e in events {
                let r = LaneGeometry.rect(e, zoom: zoom, height: size.height)
                var ring = r
                switch e.type {
                case .tap:
                    ctx.fill(Path(roundedRect: r, cornerRadius: min(r.width / 2, 3), style: .continuous), with: .color(Theme.accent))
                case .rumble:
                    ring = CGRect(x: r.minX, y: base - full, width: r.width, height: full)
                    let pts = e.intensityCurve.isEmpty
                        ? [CurvePoint(time: 0, value: 1), CurvePoint(time: e.duration, value: 1)]
                        : e.intensityCurve
                    var line = Path()
                    var area = Path()
                    area.move(to: CGPoint(x: e.start * zoom, y: base))
                    for (i, p) in pts.enumerated() {
                        let pt = CGPoint(x: (e.start + p.time) * zoom, y: base - full * e.intensity * p.value)
                        if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                        area.addLine(to: pt)
                    }
                    area.addLine(to: CGPoint(x: e.end * zoom, y: base))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(
                        Gradient(colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0.12)]),
                        startPoint: CGPoint(x: 0, y: base - full), endPoint: CGPoint(x: 0, y: base)
                    ))
                    ctx.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                case .tickTrain:
                    // Zoomed out, single ticks would merge into a solid block. Show the span instead.
                    if e.repetitionInterval * zoom < 4 {
                        ctx.fill(Path(roundedRect: r, cornerRadius: 3, style: .continuous), with: .color(Theme.accent.opacity(0.28)))
                        ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 1.5)), with: .color(Theme.accent))
                    } else {
                        for k in 0..<e.repetitionCount {
                            let x = (e.start + Double(k) * e.repetitionInterval) * zoom
                            ctx.fill(Path(roundedRect: CGRect(x: x, y: r.minY, width: 2, height: r.height), cornerRadius: 1), with: .color(Theme.accent))
                        }
                    }
                }
                if selection.contains(e.id) {
                    ctx.stroke(Path(roundedRect: ring.insetBy(dx: -2, dy: -2), cornerRadius: 4, style: .continuous), with: .color(Theme.ink.opacity(0.9)), lineWidth: 1.5)
                    if e.type == .rumble {
                        for x in [ring.minX, ring.maxX] {
                            let grip = CGRect(x: x - 1.5, y: ring.midY - 8, width: 3, height: 16)
                            ctx.fill(Path(roundedRect: grip, cornerRadius: 1.5), with: .color(Theme.ink))
                        }
                    }
                }
            }
        }
    }
}
