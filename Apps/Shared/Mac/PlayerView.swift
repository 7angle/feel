// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

import AVFoundation
import SwiftUI

final class PlayerNSView: NSView {
    static let cornerRadius: CGFloat = 12
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.cornerRadius = Self.cornerRadius
        playerLayer.cornerCurve = .continuous
        playerLayer.masksToBounds = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    var cornerRadius = PlayerNSView.cornerRadius

    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView()
        v.playerLayer.player = player
        v.playerLayer.cornerRadius = cornerRadius
        return v
    }

    func updateNSView(_ v: PlayerNSView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}
