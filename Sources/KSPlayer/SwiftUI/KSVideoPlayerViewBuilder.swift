//
//  KSVideoPlayerViewBuilder.swift
//
//
//  Created by Ian Magallan Bosch on 17.03.24.
//

import SwiftUI

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
enum KSVideoPlayerViewBuilder {
    @MainActor
    static func playbackControlView(config: KSVideoPlayer.Coordinator, spacing: CGFloat? = nil) -> some View {
        HStack(spacing: spacing) {
            // Playback controls don't need spacers for visionOS, since the controls are laid out in a HStack.
            #if os(xrOS)
            backwardButton(config: config)
            playButton(config: config)
            forwardButton(config: config)
            #else
            Spacer()
            backwardButton(config: config)
            Spacer()
            playButton(config: config)
            Spacer()
            forwardButton(config: config)
            Spacer()
            #endif
        }
    }

    @MainActor
    static func contentModeButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isScaleAspectFill.toggle()
        } label: {
            Image(systemName: config.isScaleAspectFill ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
        }
    }

    @MainActor
    static func subtitleButton(config: KSVideoPlayer.Coordinator) -> some View {
        MenuView(selection: Binding {
            config.playerLayer?.subtitleModel.selectedSubtitleInfo?.subtitleID
        } set: { value in
            let info = config.playerLayer?.subtitleModel.subtitleInfos.first { $0.subtitleID == value }
            config.playerLayer?.subtitleModel.selectedSubtitleInfo = info
            if let info = info as? MediaPlayerTrack {
                // 因为图片字幕想要实时的显示，那就需要seek。所以需要走select track
                config.playerLayer?.player.select(track: info)
            }
        }) {
            Text("Off").tag(nil as String?)
            ForEach(config.playerLayer?.subtitleModel.subtitleInfos ?? [], id: \.subtitleID) { track in
                Text(track.name).tag(track.subtitleID as String?)
            }
        } label: {
            // ⚑ `.fill` DROPPED — the label closure loads "text.bubble".
            Image(systemName: "text.bubble")
        }
    }

    @MainActor
    static func playbackRateButton(playbackRate: Binding<Float>) -> some View {
        MenuView(selection: playbackRate) {
            ForEach([0.5, 1.0, 1.25, 1.5, 2.0] as [Float]) { value in
                // 需要有一个变量text。不然会自动帮忙加很多0
                let text = "\(value) x"
                Text(text).tag(value)
            }
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
    }

    @MainActor
    static func titleView(title: String, config: KSVideoPlayer.Coordinator) -> some View {
        HStack {
            Text(title)
                .font(.title3)
            ProgressView()
                .opacity(config.state == .buffering ? 1 : 0)
        }
    }

    @MainActor
    static func muteButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            config.isMuted.toggle()
        } label: {
            Image(systemName: config.isMuted ? speakerDisabledSystemName : speakerSystemName)
        }
        .shadow(color: .black, radius: 1)
    }

    static func infoButton(showVideoSetting: Binding<Bool>) -> some View {
        Button {
            showVideoSetting.wrappedValue.toggle()
        } label: {
            // ⚑ `.fill` DROPPED — the label closure loads "info.circle".
            Image(systemName: "info.circle")
        }
        // iOS 模拟器加keyboardShortcut会导致KSVideoPlayer.Coordinator无法释放。真机不会有这个问题
        #if !os(tvOS)
        .keyboardShortcut("i", modifiers: [.command])
        #endif
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
private extension KSVideoPlayerViewBuilder {
    // ⚑ ALL FOUR ARE UNCONDITIONAL IN THE BINARY. The `#if os(xrOS)` split was the
    //   reconstruction's own: the label closures load ONE literal each, with no platform branch and
    //   no second candidate anywhere in the extent. Three of the four resolve to what the xrOS arm
    //   already said; `speakerSystemName` resolves to a value NEITHER arm carried.
    static var playSystemName: String { "play.fill" }

    static var pauseSystemName: String { "pause.fill" }

    public static var speakerSystemName: String { "speaker.wave.2.fill" }

    public static var speakerDisabledSystemName: String { "speaker.slash.fill" }

    @MainActor
    @ViewBuilder
    static func backwardButton(config: KSVideoPlayer.Coordinator) -> some View {
        if config.playerLayer?.player.seekable ?? false {
            Button {
                config.skip(interval: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.largeTitle)
            }
            #if !os(tvOS)
            .keyboardShortcut(.leftArrow, modifiers: .none)
            #endif
        }
    }

    @MainActor
    @ViewBuilder
    static func forwardButton(config: KSVideoPlayer.Coordinator) -> some View {
        if config.playerLayer?.player.seekable ?? false {
            Button {
                config.skip(interval: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.largeTitle)
            }
            #if !os(tvOS)
            .keyboardShortcut(.rightArrow, modifiers: .none)
            #endif
        }
    }

    @MainActor
    static func playButton(config: KSVideoPlayer.Coordinator) -> some View {
        Button {
            if config.state.isPlaying {
                config.playerLayer?.pause()
            } else {
                config.playerLayer?.play()
            }
        } label: {
            // ⚑ FOUR arms, not three — `.playedToTheEnd` selects "restart.circle.fill", which the
            //   three-arm spelling had no way to reach.
            Image(systemName: config.state == .error ? "play.slash.fill"
                : config.state == .playedToTheEnd ? "restart.circle.fill"
                : (config.state.isPlaying ? pauseSystemName : playSystemName))
                .font(.largeTitle)
        }
        #if os(xrOS)
        .contentTransition(.symbolEffect(.replace))
        #endif
        #if !os(tvOS)
        .keyboardShortcut(.space, modifiers: .none)
        #endif
    }
}
