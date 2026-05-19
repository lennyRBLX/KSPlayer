//
//  PipPlayerView.swift
//  KSPlayer
//
//  Forward addition (RE): SwiftUI view for PiP player controls.
//
//  Binary: $s8KSPlayer13PipPlayerViewV (VWT + 1 function)
//  RE source: Forward v1.3.15
//

import SwiftUI

public struct PipPlayerView: View {
    @ObservedObject var playerLayer: KSPlayerLayer

    public init(playerLayer: KSPlayerLayer) {
        self.playerLayer = playerLayer
    }

    public var body: some View {
        VStack {
            buildControlButtons()
        }
    }

    // RE: PipPlayerView_buildControlButtons @ 0x1014b0e10
    @ViewBuilder
    private func buildControlButtons() -> some View {
        HStack(spacing: 20) {
            Button(action: {
                playerLayer.seek(time: playerLayer.player?.currentPlaybackTime ?? 0 - 15)
            }) {
                Image(systemName: "gobackward.15")
            }

            Button(action: {
                if playerLayer.player?.isPlaying == true {
                    playerLayer.pause()
                } else {
                    playerLayer.play()
                }
            }) {
                Image(systemName: playerLayer.player?.isPlaying == true ? "pause.fill" : "play.fill")
            }

            Button(action: {
                playerLayer.seek(time: playerLayer.player?.currentPlaybackTime ?? 0 + 15)
            }) {
                Image(systemName: "goforward.15")
            }
        }
        .font(.title)
    }
}
