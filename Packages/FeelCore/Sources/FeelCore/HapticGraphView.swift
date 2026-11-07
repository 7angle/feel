// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import SwiftUI

/// Where the haptics are, over a timeline. Accent up to the playhead, because you felt it.
public struct HapticGraphView: View {
    let levels: [Double]
    let progress: Double
    let accent: Color

    public init(levels: [Double], progress: Double, accent: Color) {
        self.levels = levels
        self.progress = progress
        self.accent = accent
    }

    public var body: some View {
        Canvas { ctx, size in
            guard !levels.isEmpty else { return }
            let step = size.width / CGFloat(max(levels.count - 1, 1))
            let point = { (i: Int) in CGPoint(x: CGFloat(i) * step, y: size.height * (1 - CGFloat(levels[i]))) }
            // Each level pulls the line toward it, so the line has no corners.
            var line = Path()
            line.move(to: point(0))
            for i in 1..<max(levels.count, 1) {
                let a = point(i - 1), b = point(i)
                line.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
            }
            line.addLine(to: point(levels.count - 1))
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            let split = size.width * CGFloat(min(max(progress, 0), 1))
            let fade = { (color: Color, top: Double) in
                GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [color.opacity(top), color.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
                )
            }
            var played = ctx
            played.clip(to: Path(CGRect(x: 0, y: 0, width: split, height: size.height)))
            played.fill(area, with: fade(accent, 0.7))
            played.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var rest = ctx
            rest.clip(to: Path(CGRect(x: split, y: 0, width: size.width - split, height: size.height)))
            rest.fill(area, with: fade(.white, 0.4))
            rest.stroke(line, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
