// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AppKit
import SwiftUI

/// Draggable divider. `vertical` line resizes width, `horizontal` line resizes height.
struct Splitter: View {
    enum Axis { case vertical, horizontal }

    let axis: Axis
    @Binding var size: Double
    let range: ClosedRange<Double>
    /// True when growing the pane means dragging toward the origin (left or up).
    var invert = false

    @State private var startSize: Double?
    @State private var hovering = false

    var body: some View {
        let active = hovering || startSize != nil
        Color.clear
            .frame(width: axis == .vertical ? 8 : nil, height: axis == .horizontal ? 8 : nil)
            .overlay {
                Capsule()
                    .fill(Theme.ink.opacity(active ? 0.4 : 0))
                    .frame(width: axis == .vertical ? 3 : 36, height: axis == .horizontal ? 3 : 36)
                    .animation(Theme.state, value: active)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .dragCursor(isDragging: startSize != nil)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        if startSize == nil { startSize = size }
                        let delta = axis == .vertical ? v.translation.width : v.translation.height
                        size = min(max((startSize ?? size) + (invert ? -delta : delta), range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startSize = nil }
            )
            .onTapGesture(count: 2) { size = (range.lowerBound + range.upperBound) / 2 }
    }
}
