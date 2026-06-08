//
//  PipPlayerView.swift
//  KSPlayer
//
//  RE-reconstructed: SwiftUI overlay for the floating Picture-in-Picture
//  window controls (enter full-screen, close, move/reposition, mute).
//
//  Binary: $s8KSPlayer13PipPlayerViewV (VWT + buildControlButtons)
//  RE source: v1.3.15
//

import SwiftUI

/// Floating Picture-in-Picture control overlay.
///
/// Renders the four PiP-window controls — enter full-screen, close, move
/// (cycle corner), and mute — each wired into the tvOS focus engine via
/// `@FocusState`. `alignment` drives which corner the floating window/controls
/// sit in; `block` is the host callback invoked when the user enters full-screen
/// (`block(true)`) or closes PiP (`block(false)`).
///
/// RE: KSPlayer.PipPlayerView (types.json, 5 fields)
public struct PipPlayerView: View {
    /// Focus targets of the floating PiP control overlay.
    ///
    /// Raw ordinal order is significant (matches the binary's `.focused(_:equals:)`
    /// constants 0…3 emitted in `buildControlButtons`).
    ///
    /// RE: ENUM_CASES_1.3.15 / section 18.6 — pipFull=0, pipClose=1, pipMove=2, mute=3
    public enum FocusableView: Int {
        case pipFull    // 0 — enter full screen
        case pipClose   // 1 — close PiP
        case pipMove    // 2 — move / reposition window
        case mute       // 3 — toggle mute
    }

    // Field #1 — plain stored reference (types.json lists `playerLayer : KSPlayer.KSPlayerLayer`,
    // i.e. NOT property-wrapper-backed; the 5-field count wraps only _alignment/_focusableView/_isMuted).
    let playerLayer: KSPlayerLayer

    // Field #2 — placement of the floating PiP window/controls.
    @Binding var alignment: Alignment

    // Field #3 — host callback: block(true) on enter-full-screen, block(false) on close.
    let block: (Bool) -> Void

    // Field #4 — drives focus navigation across the four PiP control buttons (tvOS focus engine).
    @FocusState var focusableView: FocusableView?

    // Field #5 — local mute toggle state backing the mute control button.
    @State var isMuted: Bool = false

    public init(playerLayer: KSPlayerLayer,
                alignment: Binding<Alignment>,
                block: @escaping (Bool) -> Void) {
        self.playerLayer = playerLayer
        self._alignment = alignment
        self.block = block
    }

    public var body: some View {
        buildControlButtons()
    }

    /// Builds the four floating-PiP control buttons (full-screen, close, move, mute),
    /// each bound to its `FocusableView` focus target.
    ///
    /// RE: PipPlayerView_buildControlButtons @ 0x1014B0E10
    @ViewBuilder
    private func buildControlButtons() -> some View {
        HStack(spacing: 20) {
            // 1 — pipFull: enter full screen via block(true). Icon "pip.exit".
            // RE: action FUN_1014b24b0 -> FUN_1014b176c(ctx, _, 1) => block(true)
            Button {
                block(true)
            } label: {
                Image(systemName: "pip.exit")
            }
            .focused($focusableView, equals: .pipFull)

            // 2 — pipClose: close PiP via block(false). Icon "x.circle.fill".
            // RE: action FUN_1014b2540 -> FUN_1014b176c(ctx, _, 0) => block(false)
            Button {
                block(false)
            } label: {
                Image(systemName: "x.circle.fill")
            }
            .focused($focusableView, equals: .pipClose)

            // 3 — pipMove: cycle the floating window to the next corner.
            // RE: action FUN_1014b2560 -> FUN_1014b1928 (alignment cycle);
            //     label FUN_1014b2568 -> FUN_1014b1b14 (corner-reflecting icon).
            Button {
                cycleAlignment()
            } label: {
                Image(systemName: moveIconName(for: alignment))
            }
            .focused($focusableView, equals: .pipMove)

            // 4 — mute: toggle player + local state. Icon reflects mute state.
            // RE: action FUN_1014b25bc -> FUN_1014b1c9c (toggle player.isMuted + State);
            //     label FUN_1014b25c4 -> FUN_1014b1e3c (speaker.slash.fill / speaker.wave.2.fill).
            Button {
                toggleMute()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .focused($focusableView, equals: .mute)
        }
        .font(.title)
    }

    /// Cycles the floating PiP window through the four corners.
    ///
    /// Order recovered from the binary: topTrailing -> topLeading ->
    /// bottomLeading -> bottomTrailing -> topTrailing.
    ///
    /// RE: FUN_1014b1928 (pipMove action body)
    private func cycleAlignment() {
        switch alignment {
        case .topTrailing:
            alignment = .topLeading
        case .topLeading:
            alignment = .bottomLeading
        case .bottomLeading:
            alignment = .bottomTrailing
        default:
            alignment = .topTrailing
        }
    }

    /// Picks the move-button SF Symbol reflecting the window's current corner.
    ///
    /// RE: FUN_1014b1b14 (pipMove label body) — inset.filled.<corner>.rectangle
    private func moveIconName(for alignment: Alignment) -> String {
        switch alignment {
        case .topTrailing:
            return "inset.filled.toptrailing.rectangle"
        case .topLeading:
            return "inset.filled.topleading.rectangle"
        case .bottomLeading:
            return "inset.filled.bottomleading.rectangle"
        default:
            return "inset.filled.bottomtrailing.rectangle"
        }
    }

    /// Toggles the underlying player's mute and mirrors it into local state.
    ///
    /// Atmos constraint preserved: mute flows through the AVPlayer-backed
    /// `MediaPlayerProtocol.isMuted`, never an AVAudioEngine path.
    ///
    /// RE: FUN_1014b1c9c (mute action body) — get player.isMuted (vtable +0x78),
    ///     invert, set back (vtable +0x68), then write State.
    private func toggleMute() {
        let newValue = !playerLayer.player.isMuted
        playerLayer.player.isMuted = newValue
        isMuted = newValue
    }
}
