//
//  File.swift
//  KSPlayer
//
//  Created by kintan on 2022/1/29.
//
import Combine
import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
@MainActor
public struct KSVideoPlayerView: View {
    @StateObject
    private var model: KSVideoPlayerModel
    private let subtitleDataSource: (any SubtitleDataSource)?
    private let liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> ())?
    @Environment(\.dismiss)
    private var dismiss
    @State
    private var longPressSuccess = false

    public init(model: StateObject<KSVideoPlayerModel>, subtitleDataSource: (any SubtitleDataSource)?, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> ())?) {
        _model = model
        self.subtitleDataSource = subtitleDataSource
        self.liftCycleBlock = liftCycleBlock
    }

    public init(model: StateObject<KSVideoPlayerModel>, subtitleURLs: [URL], liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> ())?) {
        let subtitleDataSource: (any SubtitleDataSource)?
        if let url = model.wrappedValue.url, !subtitleURLs.isEmpty {
            subtitleDataSource = ConstantURLSubtitleDataSource(url: url, subtitleURLs: subtitleURLs)
        } else {
            subtitleDataSource = nil
        }
        self.init(model: model, subtitleDataSource: subtitleDataSource, liftCycleBlock: liftCycleBlock)
    }

    public init(url: URL, options: KSOptions, title: String?, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> ())?) {
        self.init(
            model: .init(wrappedValue: KSVideoPlayerModel(title: title ?? url.lastPathComponent, config: nil, options: options, url: .some(url))),
            subtitleDataSource: nil,
            liftCycleBlock: liftCycleBlock
        )
    }

    public init(coordinator: KSVideoPlayer.Coordinator?, url: URL, options: KSOptions, title: String?, subtitleDataSource: (any SubtitleDataSource)?, liftCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> ())?) {
        self.init(
            model: .init(wrappedValue: KSVideoPlayerModel(title: title ?? url.lastPathComponent, config: coordinator, options: options, url: .some(url))),
            subtitleDataSource: subtitleDataSource,
            liftCycleBlock: liftCycleBlock
        )
    }

    public init(playerLayer: KSPlayerLayer) {
        self.init(
            model: .init(wrappedValue: KSVideoPlayerModel(playerLayer: playerLayer)),
            subtitleDataSource: nil,
            liftCycleBlock: nil
        )
    }

    public var body: some View {
        ZStack {
            GeometryReader { proxy in
                playView
                controllerView(playerWidth: proxy.size.width)
                #if os(tvOS)
                    .ignoresSafeArea()
                #endif
                #if os(tvOS)
                if model.showVideoSetting {
                    VideoSettingView(config: model.config, subtitleModel: model.config.playerLayer?.subtitleModel ?? SubtitleModel(), // L7: view re-root off removed Coordinator.subtitleModel; fallback is a placeholder
                subtitleTitle: model.title)
                        .modifier(FocusModifier(binding: $model.focusableView, value: .controller, focused: FocusState<Bool>()))
                }
                #endif
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .automatic)
        #if os(tvOS)
            .onPlayPauseCommand {
                if model.config.state.isPlaying {
                    model.config.playerLayer?.pause()
                } else {
                    model.config.playerLayer?.play()
                }
            }
            .onExitCommand {
                if model.config.isMaskShow {
                    model.config.isMaskShow = false
                } else {
                    switch model.focusableView {
                    case .play:
                        dismiss()
                    default:
                        model.focusableView = .play
                    }
                }
            }
        #endif
    }

    private var playView: some View {
        KSVideoPlayer(coordinator: model.config, url: model.url!, options: model.options)
            .onStateChanged { playerLayer, state in
                if state == .readyToPlay {
                    if let movieTitle = playerLayer.player.dynamicInfo.metadata["title"] {
                        model.title = movieTitle
                    }
                }
            }
            .onBufferChanged { bufferedCount, consumeTime in
                print("bufferedCount \(bufferedCount), consumeTime \(consumeTime)")
            }
            .ignoresSafeArea()
            .onAppear {
                model.focusableView = .play
                if let subtitleDataSource {
                    // ⚑ → P4 M2: addSubtitle(dataSouce:) removed; subtitle attach is M2 (§5.1)
                    _ = subtitleDataSource
                }
                // 不要加这个，不然model.config无法释放，也可以在onDisappear调用removeMonitor释放
                //                    #if os(macOS)
                //                    NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
                //                        isMaskShow = overView
                //                        return $0
                //                    }
                //                    #endif
            }

        #if os(iOS) || os(xrOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(iOS)
            .focusable(!model.config.isMaskShow)
            .modifier(FocusModifier(binding: $model.focusableView, value: .play, focused: FocusState<Bool>()))
        #endif
        #if !os(xrOS)
            .onKeyPressLeftArrow {
            model.config.skip(interval: -15)
        }
        .onKeyPressRightArrow {
            model.config.skip(interval: 15)
        }
        .onKeyPressSapce {
            if model.config.state.isPlaying {
                model.config.playerLayer?.pause()
            } else {
                model.config.playerLayer?.play()
            }
        }
        #endif
        #if os(macOS)
            .onTapGesture(count: 2) {
                guard let view = model.config.playerLayer?.player.view else {
                    return
                }
                view.window?.toggleFullScreen(nil)
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
        }
        .onExitCommand {
            model.config.playerLayer?.player.view.exitFullScreenMode()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                model.config.skip(interval: -15)
            case .right:
                model.config.skip(interval: 15)
            case .up:
                model.config.playerLayer?.player.playbackVolume += 0.2
            case .down:
                model.config.playerLayer?.player.playbackVolume -= 0.2
            @unknown default:
                break
            }
        }
        #else
        .onTapGesture {
                model.config.isMaskShow.toggle()
            }
        #endif
        #if os(tvOS)
            .onMoveCommand { direction in
            switch direction {
            case .left:
                model.config.skip(interval: -15)
            case .right:
                model.config.skip(interval: 15)
            case .up:
                model.config.mask(show: true, autoHide: false)
            case .down:
                model.focusableView = .slider
            @unknown default:
                break
            }
        }
        #else
        .onHover { _ in
                model.config.isMaskShow = true
            }
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers -> Bool in
                providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                    if let data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) {
                        // `options: nil` is read, not chosen — see openURL's own note. This site is
                        // macOS-gated and so is NOT the iOS image's caller; it is spelled to match
                        // the one call the binary does contain.
                        openURL(url, options: nil)
                    }
                }
                return true
            }
        #endif
    }

    private func controllerView(playerWidth: Double) -> some View {
        VStack {
            VideoControllerView(config: model.config, subtitleModel: model.config.playerLayer?.subtitleModel ?? SubtitleModel(), // L7: view re-root off removed Coordinator.subtitleModel; fallback is a placeholder
                title: $model.title, volumeSliderSize: playerWidth / 4)
            #if !os(xrOS)
            // 设置opacity为0，还是会去更新View。所以只能这样了
            if model.config.isMaskShow {
                VideoTimeShowView(config: model.config, model: model.config.timemodel)
                    .onAppear {
                        model.focusableView = .controller
                    }
                    .onDisappear {
                        model.focusableView = .play
                    }
            }
            #endif
        }
        #if os(xrOS)
        .ornament(visibility: model.config.isMaskShow ? .visible : .hidden, attachmentAnchor: .scene(.bottom)) {
            ornamentView(playerWidth: playerWidth)
        }
        .sheet(isPresented: $model.showVideoSetting) {
            NavigationStack {
                VideoSettingView(config: model.config, subtitleModel: model.config.playerLayer?.subtitleModel ?? SubtitleModel(), // L7: view re-root off removed Coordinator.subtitleModel; fallback is a placeholder
                subtitleTitle: model.title)
            }
            .buttonStyle(.plain)
        }
        #elseif os(tvOS)
        .padding(.horizontal, 80)
        .padding(.bottom, 80)
        .background(overlayGradient)
        #endif
        .modifier(FocusModifier(binding: $model.focusableView, value: .controller, focused: FocusState<Bool>()))
        .opacity(model.config.isMaskShow ? 1 : 0)
        .padding()
    }

    private let overlayGradient = LinearGradient(
        stops: [
            Gradient.Stop(color: .black.opacity(0), location: 0.22),
            Gradient.Stop(color: .black.opacity(0.7), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    private func ornamentView(playerWidth: Double) -> some View {
        VStack(alignment: .leading) {
            KSVideoPlayerViewBuilder.titleView(title: model.title, config: model.config)
            ornamentControlsView(playerWidth: playerWidth)
        }
        .frame(width: playerWidth / 1.5)
        .buttonStyle(.plain)
        .padding(.vertical, 24)
        .padding(.horizontal, 36)
        #if os(xrOS)
            .glassBackgroundEffect()
        #endif
    }

    private func ornamentControlsView(playerWidth _: Double) -> some View {
        HStack {
            KSVideoPlayerViewBuilder.playbackControlView(config: model.config, spacing: 16)
            Spacer()
            VideoTimeShowView(config: model.config, model: model.config.timemodel, timeFont: .title3.monospacedDigit())
            Spacer()
            Group {
                KSVideoPlayerViewBuilder.contentModeButton(config: model.config)
                KSVideoPlayerViewBuilder.subtitleButton(config: model.config)
                KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $model.config.playbackRate)
                KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $model.showVideoSetting)
            }
            .font(.largeTitle)
        }
    }

    fileprivate enum FocusableField {
        case play, controller, info
    }

    // Forward 1.3.17 @0x101ac99ac, extent 0x101ac99ac-0x101ac9e2c (1152 B / 288 instr), OWNER_MATCH,
    // one symbol, not ICF-folded. Three of this unit's seven recorded divergences are closed here;
    // the remaining four all require the KSVideoPlayerView STRUCT RESTRUCTURE (the `@StateObject`
    // wraps `KSVideoPlayerModel`, not `KSVideoPlayer.Coordinator`, and both else-branch writes land
    // on the MODEL) and are held in verdict `KSVideoPlayerView_openURL_101ac99ac`.
    //
    // 1. THE `options:` PARAMETER IS REAL. The trie mangles this body
    //    `openURL(_: Foundation.URL, options: KSPlayer.KSOptions?) -> ()`, and the body's third
    //    conditional branch `cbz x28, 0x101ac9c98` is that parameter's nil test, off the prologue
    //    spill `stur x1, [x29,#-0x90]`.
    //    ⚠️ NO `= nil` DEFAULT IS WRITTEN, and the reason matters. An earlier note argued the
    //    default is absent because no `…fA0_` generator exists for it. That argument is UNSOUND:
    //    the export trie carries ZERO default-argument generators across all 57,138 symbols, along
    //    with zero closures, thunks and outlined helpers, so a generator would be missing whether
    //    or not a default was written. Whether a default exists is NOT DECIDABLE by any oracle in
    //    scripts/. What IS read is the CALL: this method has exactly one caller in the IMAGE and it
    //    passes an immediate zero (`mov x1, #0x0` at 0x101aca4b4, an immediate rather than a load
    //    from self — note `model.options` is in scope there and is deliberately not what is passed).
    //    That caller is an unnamed async funclet, NOT the macOS-gated drop handler at :219 below,
    //    which the iOS image cannot contain; :219 is spelled to match the one call that IS read.
    //    ⚑[tool=export_trie_oracle ref=KSVideoPlayerView.openURL:0x101ac99ac result=OWNER_MATCH-1-symbol]
    //
    // 2. `runOnMainThread { }` IS NOT IN THE BINARY — the body is straight-line. `runOnMainThread`
    //    exists at 0x101a03e88 and is never called; an exhaustive scan of the extent finds zero
    //    `swift_allocObject`, zero `dispatch_async` and zero `swift_task_*`, so no closure context
    //    is ever formed. The enclosing struct is already `@MainActor`, so dropping it changes no
    //    semantics. ⚑[tool=disassemble ref=openURL:0x101ac99ac result=0-closure-0-async-glue]
    //
    // 3. `else if url.isAudio || url.isMovie` DOES NOT EXIST — the else is entered unguarded. The
    //    whole 288-instruction extent contains exactly THREE conditional branches: `tbz w20,#0x0`
    //    (the isSubtitle test), `cbz x22` (playerLayer nil, inside the subtitle arm) and `cbz x28`
    //    (options nil, inside the else). `URL.isAudio` @0x1019f2ad0 and `URL.isMovie` @0x1019f28f0
    //    both exist and neither is called.
    //    ⚑[tool=disassemble ref=openURL:0x101ac99ac result=3-cond-branches-tbz-cbz-cbz]
    //
    // `url.isSubtitle` is likewise never called out-of-line — the optimiser inlined it into a
    // membership test against a static 5-element `["ass","srt","ssa","vtt","sup"]` at 0x1044e72c0.
    // Spelling it `url.isSubtitle` matches the semantics; the inlining is the compiler's.
    public func openURL(_ url: URL, options: KSOptions?) {
        if url.isSubtitle {
            let info = URLSubtitleInfo(url: url)
            // ⚑ CORRECTED — this never went through a subtitle model. openURL @0x101ac99ac spells
            //   `playerLayer?.select(subtitleInfo:isSecondary:)` @0x1019ceb00, and both exclusivity
            //   accesses in that branch are READ (w2=0): nothing is stored. The old spelling wrote
            //   `Coordinator.subtitleModel`, a field that does not exist on Coordinator in the
            //   binary at all — `subtitleModel` lives on KSPlayerLayer. The callee is already
            //   `public` at KSPlayerLayer.swift:872.
            // ⚑[tool=export_trie_oracle ref=KSPlayerLayer.select(subtitleInfo:isSecondary:):0x1019ceb00 result=LOCATED]
            model.config.playerLayer?.select(subtitleInfo: info, isSecondary: false)
        } else {
            if let options {
                model.options = options
            }
            model.url = url
            model.title = url.lastPathComponent
        }
    }
}

extension View {
    func onKeyPressLeftArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.leftArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func onKeyPressRightArrow(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.rightArrow) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }

    func onKeyPressSapce(action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            return onKeyPress(.space) {
                action()
                return .handled
            }
        } else {
            return self
        }
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
struct VideoControllerView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var subtitleModel: SubtitleModel
    @Binding
    fileprivate var title: String
    fileprivate var volumeSliderSize: Double?
    @State
    private var showVideoSetting = false
    @Environment(\.dismiss)
    private var dismiss
    public var body: some View {
        VStack {
            #if os(tvOS)
            Spacer()
            HStack {
                Text(title)
                    .lineLimit(2)
                    .layoutPriority(3)
                ProgressView()
                    .opacity(config.state == .buffering ? 1 : 0)
                Spacer()
                    .layoutPriority(2)
                HStack {
                    Button {
                        if config.state.isPlaying {
                            config.playerLayer?.pause()
                        } else {
                            config.playerLayer?.play()
                        }
                    } label: {
                        Image(systemName: config.state == .error ? "play.slash.fill" : (config.state.isPlaying ? "pause.circle.fill" : "play.circle.fill"))
                    }
                    .frame(width: 56)
                    if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                        audioButton(audioTracks: audioTracks)
                    }
                    muteButton
                        .frame(width: 56)
                    contentModeButton
                        .frame(width: 56)
                    subtitleButton
                    playbackRateButton
                    pipButton
                        .frame(width: 56)
                    infoButton
                        .frame(width: 56)
                }
                .font(.caption)
            }
            #else
            HStack {
                #if !os(xrOS)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "x.circle.fill")
                }
                #if !os(tvOS)
                if config.playerLayer?.player.allowsExternalPlayback == true {
                    AirPlayView().fixedSize()
                }
                #endif
                #endif
                Spacer()
                if let audioTracks = config.playerLayer?.player.tracks(mediaType: .audio), !audioTracks.isEmpty {
                    audioButton(audioTracks: audioTracks)
                    #if os(xrOS)
                        .aspectRatio(1, contentMode: .fit)
                        .glassBackgroundEffect()
                    #endif
                }
                muteButton
                #if !os(xrOS)
                contentModeButton
                subtitleButton
                #endif
            }
            Spacer()
            #if !os(xrOS)
            KSVideoPlayerViewBuilder.playbackControlView(config: config)
            Spacer()
            HStack {
                KSVideoPlayerViewBuilder.titleView(title: title, config: config)
                Spacer()
                playbackRateButton
                pipButton
                infoButton
            }
            #endif
            #endif
        }
        #if !os(tvOS)
        .font(.title)
        .buttonStyle(.borderless)
        #endif
        .sheet(isPresented: $showVideoSetting) {
            VideoSettingView(config: config, subtitleModel: config.playerLayer?.subtitleModel ?? SubtitleModel(), // L7: view re-root off removed Coordinator.subtitleModel; fallback is a placeholder
                subtitleTitle: title)
        }
    }

    private var muteButton: some View {
        #if os(xrOS)
        HStack {
            Slider(value: $config.playbackVolume, in: 0 ... 1)
                .onChange(of: config.playbackVolume) { _, newValue in
                    config.isMuted = newValue == 0
                }
                .frame(width: volumeSliderSize ?? 100)
                .tint(.white.opacity(0.8))
                .padding(.leading, 16)
            KSVideoPlayerViewBuilder.muteButton(config: config)
        }
        .padding(16)
        .glassBackgroundEffect()
        #else
        KSVideoPlayerViewBuilder.muteButton(config: config)
        #endif
    }

    private var contentModeButton: some View {
        KSVideoPlayerViewBuilder.contentModeButton(config: config)
    }

    private func audioButton(audioTracks: [MediaPlayerTrack]) -> some View {
        MenuView(selection: Binding {
            audioTracks.first { $0.isEnabled }?.trackID
        } set: { value in
            if let track = audioTracks.first(where: { $0.trackID == value }) {
                config.playerLayer?.player.select(track: track)
            }
        }) {
            ForEach(audioTracks, id: \.trackID) { track in
                Text(track.description).tag(track.trackID as Int32?)
            }
        } label: {
            Image(systemName: "waveform.circle.fill")
            #if os(xrOS)
                .padding()
                .clipShape(Circle())
            #endif
        }
    }

    private var subtitleButton: some View {
        KSVideoPlayerViewBuilder.subtitleButton(config: config)
    }

    private var playbackRateButton: some View {
        KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $config.playbackRate)
    }

    private var pipButton: some View {
        Button {
            // ⚑ THE PIN IS DISCHARGED — this body IS located and read now, at 0x101ad0438, and it
            //   DIFFERS from the patterned spelling that stood here. A nil `pipController` does not
            //   fall through doing nothing: it takes the START branch, same as a non-active one.
            //   The old `let pipController = …` binding made nil a no-op, which is the one shape the
            //   binary does not have.
            if let layer = config.playerLayer as? KSComplexPlayerLayer {
                if layer.player.pipController?.isPictureInPictureActive == true {
                    layer.player.pipController?.stop(restoreUserInterface: true)
                } else {
                    layer.pipStart()
                }
            }
        } label: {
            // ⚑ The glyph is the three-character small string "pip", not this SF name.
            Image(systemName: "pip")
        }
    }

    private var infoButton: some View {
        KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
    }
}

@available(iOS 15, tvOS 15, macOS 12, *)
struct VideoTimeShowView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var model: ControllerTimeModel
    // ⚑ NON-OPTIONAL. The binary's field mangle carries no trailing `Sg`, so this is `Font`, not
    //   `Font?`. The default below is the value the two `?? .caption2.monospacedDigit()` fallbacks
    //   were already supplying, so the observable result at every call site is unchanged — including
    //   the one construction that passes no `timeFont:` at all. ⚑ default spelling approved=jweaver:
    //   the binary fixes the TYPE, not which Font literal the declaration defaults to.
    fileprivate var timeFont: Font = .caption2.monospacedDigit()
    public var body: some View {
        if config.playerLayer?.player.seekable ?? false {
            HStack {
                Text(model.currentTime.toString(for: .minOrHour)).font(timeFont)
                Slider(value: Binding {
                    Float(model.currentTime)
                } set: { newValue, _ in
                    model.currentTime = Int(newValue)
                }, in: 0 ... Float(model.totalTime)) { onEditingChanged in
                    if onEditingChanged {
                        config.playerLayer?.pause()
                    } else {
                        config.seek(time: TimeInterval(model.currentTime))
                    }
                }
                .frame(maxHeight: 20)
                #if os(xrOS)
                    .tint(.white.opacity(0.8))
                #endif
                Text((model.totalTime).toString(for: .minOrHour)).font(timeFont)
            }
            .font(.system(.title2))
        } else {
            Text("Live Streaming")
        }
    }
}

extension EventModifiers {
    static let none = Self()
}

@available(iOS 16, tvOS 16, macOS 13, *)
struct VideoSubtitleView: View {
    @ObservedObject
    fileprivate var model: SubtitleModel
    var body: some View {
        ZStack {
            ForEach(model.parts) { part in
                part.subtitleView
            }
        }
    }

    fileprivate static func imageView(_ image: UIImage) -> some View {
        #if enableFeatureLiveText && canImport(VisionKit) && !targetEnvironment(simulator)
        if #available(macCatalyst 17.0, *) {
            return LiveTextImage(uiImage: image)
        } else {
            return Image(uiImage: image)
                .resizable()
        }
        #else
        return Image(uiImage: image)
            .resizable()
        #endif
    }
}

private extension SubtitlePart {
    @available(iOS 16, tvOS 16, macOS 13, *)
    @MainActor
    var subtitleView: some View {
        // ⚑ UNRESOLVED → P4 M2: render `render` (Either<SubtitleImageInfo,SubtitleTextInfo>) —
        //   recon image/text/textPosition removed (payload consolidated into render, §8.6).
        Text("")
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
struct VideoSettingView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var subtitleModel: SubtitleModel
    @State
    fileprivate var subtitleTitle: String
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        PlatformView {
            let videoTracks = config.playerLayer?.player.tracks(mediaType: .video)
            if let videoTracks, !videoTracks.isEmpty {
                Picker(selection: Binding {
                    videoTracks.first { $0.isEnabled }?.trackID
                } set: { value in
                    if let track = videoTracks.first(where: { $0.trackID == value }) {
                        config.playerLayer?.player.select(track: track)
                    }
                }) {
                    ForEach(videoTracks, id: \.trackID) { track in
                        Text(track.description).tag(track.trackID as Int32?)
                    }
                } label: {
                    Label("Video Track", systemImage: "video.fill")
                }
                LabeledContent("Video Type", value: (videoTracks.first { $0.isEnabled }?.dynamicRange ?? .sdr).description)
            }
            TextField("Sutitle delay", value: $subtitleModel.subtitleDelay, format: .number)
            TextField("Title", text: $subtitleTitle)
            Button("Search Sutitle") {
                subtitleModel.searchSubtitle(query: subtitleTitle, languages: ["zh-cn"])
            }
            LabeledContent("Stream Type", value: (videoTracks?.first { $0.isEnabled }?.fieldOrder ?? .progressive).description)
            if let dynamicInfo = config.playerLayer?.player.dynamicInfo {
                DynamicInfoView(dynamicInfo: dynamicInfo)
            }
            if let fileSize = config.playerLayer?.player.fileSize, fileSize > 0 {
                LabeledContent("File Size", value: fileSize.kmFormatted + "B")
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst) || os(xrOS)
        .toolbar {
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        #endif
    }
}

@available(iOS 16, tvOS 16, macOS 13, *)
public struct DynamicInfoView: View {
    @ObservedObject
    fileprivate var dynamicInfo: DynamicInfo
    public var body: some View {
        LabeledContent("Display FPS", value: dynamicInfo.displayFPS, format: .number)
        LabeledContent("Audio Video sync", value: dynamicInfo.audioVideoSyncDiff, format: .number)
        LabeledContent("Dropped Frames", value: dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount, format: .number)
        LabeledContent("Bytes Read", value: dynamicInfo.bytesRead.kmFormatted + "B")
        LabeledContent("Audio bitrate", value: dynamicInfo.audioBitrate.kmFormatted + "bps")
        LabeledContent("Video bitrate", value: dynamicInfo.videoBitrate.kmFormatted + "bps")
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct KSVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "http://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")!
        KSVideoPlayerView(coordinator: KSVideoPlayer.Coordinator(), url: url, options: KSOptions(), title: nil, subtitleDataSource: nil, liftCycleBlock: nil)
    }
}

// struct AVContentView: View {
//    var body: some View {
//        StructAVPlayerView().frame(width: UIScene.main.bounds.width, height: 400, alignment: .center)
//    }
// }
//
// struct StructAVPlayerView: UIViewRepresentable {
//    let playerVC = AVPlayerViewController()
//    typealias UIViewType = UIView
//    func makeUIView(context _: Context) -> UIView {
//        playerVC.view
//    }
//
//    func updateUIView(_: UIView, context _: Context) {
//        playerVC.player = AVPlayer(url: URL(string: "https://bitmovin-a.akamaihd.net/content/dataset/multi-codec/hevc/stream_fmp4.m3u8")!)
//    }
// }

//  Reconstructed from Forward-TF 1.3.17. Class descriptor 0x1039f24cc.
// Root class: SuperclassType @ desc+0x14 reads 0, which is the "no superclass" encoding.
// ⚑[tool=fieldrec ref=KSVideoPlayerModel:0x1039f24cc result=NumFields-8]
// Unlike CustomProgressView, this class is richly named: the orphaned export trie carries 73
// symbols for it, so every member below is READ, not invented.
// ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel:0x1039f24cc result=73-symbols]
// `@MainActor` is DERIVED, not stylistic. The binary calls `KSVideoPlayer.Coordinator.init()`
// (0x101acc684) and reads `Coordinator.playerLayer` synchronously from next()/previous(); that
// Coordinator is declared `@MainActor public final class` at KSVideoPlayer.swift:73-74, and Swift
// permits a synchronous call into MainActor-isolated state only from a MainActor-isolated caller.
// The isolation is therefore forced by the call graph the binary already contains.
@MainActor
public class KSVideoPlayerModel: ObservableObject {
    // Nested enum, descriptor 0x1039f266c, FieldDescriptor 0x103cbe88c, NumFields=3, all three
    // records carrying an EMPTY mangled type — i.e. three payload-free cases, in this order.
    // The `O` in `...AC09FocusableF0OSgvpfP` is what identifies it as an enum rather than a class.
    // ⚑[tool=fieldrec ref=KSVideoPlayerModel.FocusableView:0x1039f266c result=3-empty-cases]
    enum FocusableView {
        case play
        case controller
        case slider
    }

    // NULL-flag alignment (l2-block-deferral-vs-spelling #5). The field RECORD carries only the
    // descriptor's short name `Coordinator`, while the offset global 0x104c63810 and the getter
    // 0x101acb1f8 BOTH demangle to `KSPlayer.KSVideoPlayer.Coordinator`. Bare `Coordinator` does
    // not resolve here (the type is nested in KSVideoPlayer), so this alias aligns the source text
    // with the record. A typealias is erased and leaves NO binary artifact, so which spelling the
    // original source used is UNDECIDABLE from the image — recorded, not presented as recovered.
    // ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel.config:0x104c63810 result=qualified-in-vpWvd]
    public typealias Coordinator = KSVideoPlayer.Coordinator

    // Field-record order is the declaration order below; it is the binary's, not a preference.
    // Access per field is read from the trie: a property descriptor (vpMV/vpZMV) is public-
    // exclusive; a `33_<hash>LL` discriminator is private; neither means internal.
    // Declaration defaults are read from the vpfi bodies, not assumed.
    // ⚑[tool=vpfi_initializer_oracle ref=KSVideoPlayerModel result=5-defaults-4-distinct-bodies]
    @Published public var title: String                                    // rec0 `_title`
    public var config: Coordinator                                      // rec1, NON-optional
    public var options: KSOptions                                          // rec2
    public var urls: [URL] = []                                            // rec3, __swiftEmptyArrayStorage
    @Published public var url: URL?                                        // rec4, vpfi = Optional.none
    @Published var focusableView: KSVideoPlayerModel.FocusableView?                           // rec5, internal, vpfi = 0
    @Published var showVideoSetting: Bool = false                          // rec6, internal, vpfi = 0
    private var cancellables: Set<AnyCancellable> = []                     // rec7, __swiftEmptySetSingleton

    public convenience init(playerLayer: KSPlayerLayer) {
        self.init(
            title: playerLayer.url.lastPathComponent,
            config: KSVideoPlayer.Coordinator(playerLayer: playerLayer),
            options: playerLayer.options,
            url: .some(playerLayer.url)
        )
    }

    // `config` is NON-optional in the field record (offset global 0x104c63810 demangles to
    // `... .config : KSPlayer.KSVideoPlayer.Coordinator`, no `Sg`) even though the init PARAMETER
    // is optional. The init supplies a fresh Coordinator when the argument is nil — the
    // `Coordinator.init()` call at 0x101acc684, guarded by the metadata accessor at 0x101acc670.
    // Signature is read whole from the trie, not inferred:
    // ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel.__allocating_init:0x101aca9c8 result=4-param-signature]
    //
    // ⚠️ THIS BODY IS PINNED AND INCOMPLETE — DO NOT READ IT AS A FINISHED RECONSTRUCTION.
    // The real init is at 0x101acc3a8 (allocating thunk 0x101aca9c8 tail-calls it at 0x101acaa18),
    // 1324 B / 331 instr. The four parameter assignments below are evidenced by the three named
    // field-offset stores plus the read signature. The TAIL IS NOT WRITTEN: the body continues
    // with five `Published(initialValue:)` constructions, a read of
    // `Coordinator.objectWillChange` (0x101acc74c), a `swift_weakInit` capture (0x101acc780), a
    // `Publisher.sink(receiveValue:)` (0x101acc7b4) whose AnyCancellable is `store(in:)`-ed into
    // `cancellables` (0x101acc7e4), and an assignment to
    // `Coordinator.onURLChanged : ((KSPlayerLayer, URL) -> ())?` (offset global 0x104c63568).
    // Those closures were NOT read instruction-by-instruction and are therefore not written.
    // ⚑[tool=body_fingerprint ref=KSVideoPlayerModel.init:0x101acc3a8 result=pinned-subscription-tail]
    public init(title: String, config: KSVideoPlayer.Coordinator?, options: KSOptions, url: URL?) {
        self.title = title
        self.config = config ?? KSVideoPlayer.Coordinator()
        self.options = options
        self.url = url
    }

    // vtable idx37 / slot55 (VTableOffset=18), Impl=0x101acccfc, 180 B / 45 instr. Read end to end.
    // Name is READ from the trie: `$s8KSPlayer18KSVideoPlayerModelC4nextyyF`.
    //
    // Access is declared internal (no modifier): the mangled name carries no `33_<hash>LL`
    // discriminator, so it is not private, and vtable membership rules out `final` — but nothing
    // in the binary separates internal from public for a method, so the weaker claim is written.
    // ⚑[tool=vtable_impl_oracle ref=KSVideoPlayerModel:idx37 result=slot55-Impl-0x101acccfc]
    //
    // The dispatch is virtual, through metadata byte-offset 0x3e0 = slot 124 = KSComplexPlayerLayer
    // idx12, whose Impl 0x1019d27a8 the trie names `playNextURL()`.
    // ⚑[tool=export_trie_oracle ref=KSComplexPlayerLayer.playNextURL:0x1019d27a8 result=named]
    @used func next() {
        if let layer = config.playerLayer as? KSComplexPlayerLayer {
            layer.playNextURL()
        }
    }

    // vtable idx38 / slot56, Impl=0x101accdb0, 148 B / 37 instr. Read end to end. Structurally
    // identical to next() except the call is DIRECT to 0x1019d3518 rather than virtual — that
    // address is in no vtable, which is what makes `playPreviousURL()` internal rather than public.
    // That target already carries its own invented-name marker at KSPlayerLayer.swift:1342, landed
    // by an earlier session and reasoned from this exact next/previous pairing.
    // ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel.previous:0x101accdb0 result=named]
    @used func previous() {
        if let layer = config.playerLayer as? KSComplexPlayerLayer {
            layer.playPreviousURL()
        }
    }
}
