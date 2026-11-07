// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AppKit
import SwiftUI

/// Direction: the picture is the star. Two text sizes, three grays.
/// The accent marks haptics and nothing else, so anything orange is something you feel.
enum Theme {
    /// Follows light and dark mode. Text and lines are `ink` at some opacity.
    static let ink = adaptive(light: NSColor(white: 0.07, alpha: 1), dark: .white)
    /// Opposite of `ink`, for text on an `ink` fill.
    static let paper = adaptive(light: .white, dark: NSColor(white: 0.07, alpha: 1))
    static let bg = adaptive(
        light: NSColor(red: 0.955, green: 0.95, blue: 0.94, alpha: 1),
        dark: NSColor(red: 0.075, green: 0.07, blue: 0.066, alpha: 1)
    )
    static let deck = adaptive(
        light: NSColor(red: 0.995, green: 0.99, blue: 0.985, alpha: 1),
        dark: NSColor(red: 0.11, green: 0.105, blue: 0.1, alpha: 1)
    )
    static let glassTint = adaptive(light: NSColor(white: 1, alpha: 0.4), dark: NSColor(white: 0, alpha: 0.35))
    static let wash = ink.opacity(0.06)
    static let border = ink.opacity(0.1)
    static let textPrimary = ink.opacity(0.92)
    static let textSecondary = ink.opacity(0.55)
    static let icon = ink.opacity(0.72)
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.2)
    static let danger = Color.red.opacity(0.85)
    static let font = Font.system(size: 13)
    static let fontSmall = Font.system(size: 11)
    static let radius: CGFloat = 16
    static let controlRadius: CGFloat = 7
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    static let state = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
    static let exit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }
}

extension View {
    /// Solid surface for the timeline deck.
    func deckSurface() -> some View {
        background(Theme.deck, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.border))
    }

    /// Surface for anything that floats over the stage.
    @ViewBuilder func floating(radius: CGFloat = Theme.radius) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(Theme.glassTint), in: .rect(cornerRadius: radius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.border))
        }
    }

    func sectionLabel() -> some View {
        font(Theme.fontSmall).fontWeight(.medium).foregroundStyle(Theme.textSecondary)
    }

    /// Row shape shared by sliders and number fields.
    func controlRow() -> some View {
        padding(.horizontal, 9)
            .frame(height: 28)
            .background(Theme.wash, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// Text button: hover wash, scale on press, dim when disabled.
struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, prominent ? 12 : 8)
            .frame(minHeight: 28)
            .foregroundStyle(prominent ? Theme.paper : Theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(prominent ? Theme.ink.opacity(hovering ? 1 : 0.88) : (hovering ? Theme.wash : .clear))
            )
            .opacity(enabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
            .animation(Theme.state, value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// Square icon button with a named action for tooltips and VoiceOver.
struct IconButton: View {
    let symbol: String
    let label: String
    var active = false
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: size, height: size)
        }
        .buttonStyle(IconButtonStyle(active: active))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct IconButtonStyle: ButtonStyle {
    let active: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active || hovering ? Theme.textPrimary : Theme.icon)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(active ? Theme.ink.opacity(0.14) : (hovering ? Theme.wash : .clear))
            )
            .opacity(enabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.press, value: configuration.isPressed)
            .animation(Theme.state, value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// List row with hover wash.
struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.ink.opacity(0.1) : (hovering ? Theme.wash : .clear))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.press, value: configuration.isPressed)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// On/off capsule for filters.
struct ChipStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.fontSmall)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
            .background(Capsule().fill(on ? Theme.ink.opacity(0.14) : .clear))
            .overlay(Capsule().stroke(on ? .clear : Theme.border))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.press, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// One control for label, value and slider. Drag anywhere to change. Double-click to type.
/// The drag is relative, so a click never changes the value by accident.
struct FillSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    @State private var dragStart: Double?
    @State private var hovering = false
    @State private var editing = false
    @FocusState private var focused: Bool

    private var span: Double { range.upperBound - range.lowerBound }
    private var fraction: Double { span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0 }

    private var clamped: Binding<Double> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.wash
                Theme.accent.opacity(hovering || dragStart != nil ? 0.5 : 0.38)
                    .frame(width: geo.size.width * fraction)
                HStack {
                    Text(label).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 4)
                    if editing {
                        TextField("", value: clamped, format: .number.precision(.fractionLength(0...3)))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 60)
                            .focused($focused)
                            .onSubmit { editing = false }
                            .onAppear { focused = true }
                            .onChange(of: focused) { _, now in if !now { editing = false } }
                    } else {
                        Text(format(value)).monospacedDigit()
                    }
                }
                .padding(.horizontal, 9)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        guard !editing, geo.size.width > 0 else { return }
                        let start = dragStart ?? value
                        dragStart = start
                        var next = start + Double(v.translation.width / geo.size.width) * span
                        if let step { next = (next / step).rounded() * step }
                        value = min(max(next, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { editing = true }
        }
        .frame(height: 28)
        .animation(Theme.state, value: hovering)
        .onHover { hovering = $0 }
        .dragCursor(isDragging: dragStart != nil, enabled: !editing)
        .accessibilityRepresentation {
            Slider(value: $value, in: range) { Text(label) }
                .accessibilityValue(format(value))
        }
    }
}

extension View {
    /// Open hand on hover, closed hand while dragging.
    func dragCursor(isDragging: Bool, enabled: Bool = true) -> some View {
        modifier(DragCursor(isDragging: isDragging, enabled: enabled))
    }
}

private struct DragCursor: ViewModifier {
    let isDragging: Bool
    let enabled: Bool
    @State private var hovering = false
    @State private var pushed = false

    private var wanted: NSCursor? {
        if isDragging { return .closedHand }
        return hovering && enabled ? .openHand : nil
    }

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .onChange(of: wanted) { _, next in apply(next) }
            // Pops on removal, so a closing panel never leaves the hand stuck.
            .onDisappear { apply(nil) }
    }

    private func apply(_ cursor: NSCursor?) {
        if pushed { NSCursor.pop() }
        cursor?.push()
        pushed = cursor != nil
    }
}

/// Grows with its content, then scrolls when it runs out of room.
struct HugScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.never)
        }
    }
}
