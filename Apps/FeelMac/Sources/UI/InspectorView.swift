// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import FeelCore
import SwiftUI

/// Only there while something is selected.
struct InspectorView: View {
    let model: AppModel

    var body: some View {
        HugScroll {
            VStack(alignment: .leading, spacing: 10) {
                if model.selection.count == 1, let id = model.selection.first, model.project.events.contains(where: { $0.id == id }) {
                    EventFields(e: model.binding(for: id)) { model.clearSelection() }
                } else {
                    HStack {
                        Text("\(model.selection.count) haptics selected").fontWeight(.semibold)
                        Spacer()
                        IconButton(symbol: "xmark", label: "Clear selection") { model.clearSelection() }
                    }
                    Button("Duplicate") { model.duplicateSelection() }
                    Button("Save as Preset…") { model.saveSelectionAsPreset() }
                    Button("Delete") { model.deleteSelection() }
                }
            }
            .buttonStyle(QuietButtonStyle())
            .padding(14)
            .frame(width: 272, alignment: .leading)
        }
        .floating()
    }
}

private struct EventFields: View {
    @Binding var e: HapticEvent
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("Type", selection: $e.type) {
                Text("Tap").tag(HapticEventType.tap)
                Text("Rumble").tag(HapticEventType.rumble)
                Text("Ticks").tag(HapticEventType.tickTrain)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            IconButton(symbol: "xmark", label: "Clear selection", action: close)
        }
        FillSlider(label: "Intensity", value: $e.intensity, range: 0...1)
        FillSlider(label: "Sharpness", value: $e.sharpness, range: 0...1)
        NumberRow(label: "Start", value: $e.start, range: 0...86400, unit: "s")
        switch e.type {
        case .tap:
            EmptyView()
        case .rumble:
            NumberRow(label: "Duration", value: $e.duration, range: 0.05...10, unit: "s")
            FillSlider(label: "Fade in", value: $e.fadeIn, range: 0...max(e.duration, 0.05), format: seconds)
            FillSlider(label: "Fade out", value: $e.fadeOut, range: 0...max(e.duration, 0.05), format: seconds)
            CurveEditor(title: "Intensity curve", points: $e.intensityCurve, duration: e.duration).padding(.top, 6)
            CurveEditor(title: "Sharpness curve", points: $e.sharpnessCurve, duration: e.duration)
        case .tickTrain:
            NumberRow(label: "Interval", value: $e.repetitionInterval, range: 0.02...1, unit: "s")
            Stepper(value: $e.repetitionCount, in: 1...200) {
                HStack {
                    Text("Count")
                    Spacer()
                    Text("\(e.repetitionCount)").monospacedDigit()
                }
            }
            .controlSize(.small)
            .controlRow()
        }
        if let preset = e.presetID {
            HStack {
                Text("From preset").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(HapticPresetLibrary.builtIn.first { $0.id == preset }?.name ?? "Custom")
            }
            .padding(.top, 4)
        }
    }

    private func seconds(_ v: Double) -> String { String(format: "%.2f s", v) }
}

/// Typed value in the same row shape as `FillSlider`.
struct NumberRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = ""

    private var clamped: Binding<Double> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Spacer()
            TextField(label, value: clamped, format: .number.precision(.fractionLength(0...3)))
                .labelsHidden()
                .textFieldStyle(.plain)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            if !unit.isEmpty { Text(unit).foregroundStyle(Theme.textSecondary) }
        }
        .controlRow()
    }
}

/// Click empty space: add point. Drag point: move. Double-click point: remove.
struct CurveEditor: View {
    let title: String
    @Binding var points: [CurvePoint]
    let duration: TimelineTime

    @State private var dragIndex: Int?
    private let height: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).sectionLabel()
                Spacer()
                if !points.isEmpty {
                    Button("Reset") { points = [] }.buttonStyle(.plain).font(Theme.fontSmall).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 16)
            GeometryReader { geo in
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink.opacity(0.06)))
                    var line = Path()
                    if points.isEmpty {
                        line.move(to: CGPoint(x: 0, y: 0))
                        line.addLine(to: CGPoint(x: size.width, y: 0))
                        ctx.stroke(line, with: .color(Theme.ink.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    } else {
                        for (i, p) in points.enumerated() {
                            let pt = position(p, size)
                            if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                        }
                        ctx.stroke(line, with: .color(Theme.accent), lineWidth: 1.5)
                        for p in points {
                            let c = position(p, size)
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(Theme.accent))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag(to: $0.location, size: geo.size) }
                        .onEnded { _ in dragIndex = nil }
                )
                .simultaneousGesture(
                    SpatialTapGesture(count: 2).onEnded { removeNearest(to: $0.location, size: geo.size) }
                )
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
    }

    private func position(_ p: CurvePoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: duration > 0 ? p.time / duration * size.width : 0, y: (1 - p.value) * size.height)
    }

    private func nearest(to loc: CGPoint, size: CGSize) -> Int? {
        points.indices.min { distance(position(points[$0], size), loc) < distance(position(points[$1], size), loc) }
            .flatMap { distance(position(points[$0], size), loc) < 10 ? $0 : nil }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func drag(to loc: CGPoint, size: CGSize) {
        guard duration > 0, size.width > 0 else { return }
        let t = min(max(loc.x / size.width, 0), 1) * duration
        let v = min(max(1 - loc.y / size.height, 0), 1)
        if dragIndex == nil {
            if let i = nearest(to: loc, size: size) {
                dragIndex = i
            } else {
                if points.isEmpty {
                    points = [CurvePoint(time: 0, value: 1), CurvePoint(time: duration, value: 1)]
                }
                points.append(CurvePoint(time: t, value: v))
                points.sort { $0.time < $1.time }
                dragIndex = points.firstIndex { $0.time == t && $0.value == v }
            }
        }
        guard let i = dragIndex, points.indices.contains(i) else { return }
        let lo = i > 0 ? points[i - 1].time : 0
        let hi = i < points.count - 1 ? points[i + 1].time : duration
        points[i] = CurvePoint(time: min(max(t, lo), hi), value: v)
    }

    private func removeNearest(to loc: CGPoint, size: CGSize) {
        guard let i = nearest(to: loc, size: size) else { return }
        points.remove(at: i)
        if points.count < 2 { points = [] }
    }
}
