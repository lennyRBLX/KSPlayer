//
//  File.swift
//  KSPlayer
//
//  Created by kintan on 2022/1/29.
//
import AVFoundation
import MediaPlayer
import SwiftUI

/// RE: 0x1014A35F8 (KSVideoPlayerView.init, 1.3.15) / 0x1014A36BC (body) / 0x1014A7098
/// (handleMediaURLChange). The top-level SwiftUI player screen: hosts the `KSVideoPlayer`
/// bridge, the subtitle overlay, the controller overlay, and the tvOS settings drop-down.
///
/// NOTE (model-vs-coordinator divergence): doc §18.3 records the view's primary state as a
/// `SwiftUI.StateObject<KSVideoPlayerModel>` whose `_url`/`urls` feed a
/// `ConstantURLSubtitleDataSource` branch. This upstream form holds a
/// `@StateObject KSVideoPlayer.Coordinator` directly and constructs the subtitle data source
/// from the injected `subtitleDataSource` in `onAppear`. The URL-change reaction documented as
/// `handleMediaURLChange @ 0x1014A7098` is realized here by `openURL(_:)` + the `url` `didSet`.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
@MainActor
public struct KSVideoPlayerView: View {
    private let subtitleDataSource: SubtitleDataSource?
    /// RE: doc §18.3 field #3 `liftCycleBlock` (binary typo "lift"→"life", auto-corrected).
    /// Injectable lifecycle hook invoked with `(coordinator, true)` on appear and
    /// `(coordinator, false)` on disappear.
    private let lifeCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)?
    @State
    private var title: String
    @StateObject
    private var playerCoordinator: KSVideoPlayer.Coordinator
    /// Stable aggregating model fed to the canonical §18.14 `VideoSettingView(model:)`.
    /// The settings sheet was relocated to its own cluster file and now consumes a
    /// `KSVideoPlayerModel`; this view drives the sheet from its `playerCoordinator`, so
    /// the Coordinator is wrapped once in a `@StateObject` model (kept across renders) and
    /// its `title` is mirrored from this view's `@State title` wherever that title is
    /// reassigned (the `onStateChanged` metadata handler and `openURL`).
    @StateObject
    private var videoSettingModel: KSVideoPlayerModel
    @Environment(\.dismiss)
    private var dismiss
    @FocusState
    private var focusableField: FocusableField? {
        willSet {
            isDropdownShow = newValue == .info
        }
    }

    public let options: KSOptions
    @State
    private var isDropdownShow = false
    @State
    private var showVideoSetting = false
    @State
    public var url: URL {
        didSet {
            #if os(macOS)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            #endif
        }
    }

    public init(url: URL, options: KSOptions, title: String? = nil) {
        self.init(coordinator: KSVideoPlayer.Coordinator(), url: url, options: options, title: title, subtitleDataSource: nil)
    }

    public init(coordinator: KSVideoPlayer.Coordinator, url: URL, options: KSOptions, title: String? = nil, subtitleDataSource: SubtitleDataSource? = nil, lifeCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        self.init(coordinator: coordinator, url: .init(wrappedValue: url), options: options, title: .init(wrappedValue: title ?? url.lastPathComponent), subtitleDataSource: subtitleDataSource, lifeCycleBlock: lifeCycleBlock)
    }

    public init(coordinator: KSVideoPlayer.Coordinator, url: State<URL>, options: KSOptions, title: State<String>, subtitleDataSource: SubtitleDataSource?, lifeCycleBlock: ((KSVideoPlayer.Coordinator, Bool) -> Void)? = nil) {
        _url = url
        _playerCoordinator = .init(wrappedValue: coordinator)
        _title = title
        // Wrap the same Coordinator in the aggregating model the relocated settings sheet
        // expects. Seeded with the initial title; kept in sync afterward where `title` is
        // reassigned (onStateChanged / openURL).
        _videoSettingModel = .init(wrappedValue: KSVideoPlayerModel(title: title.wrappedValue, coordinator: coordinator, options: options))
        #if os(macOS)
        NSDocumentController.shared.noteNewRecentDocumentURL(url.wrappedValue)
        #endif
        self.options = options
        self.subtitleDataSource = subtitleDataSource
        self.lifeCycleBlock = lifeCycleBlock
    }

    public var body: some View {
        ZStack {
            GeometryReader { proxy in
                playView
                HStack {
                    Spacer()
                    VideoSubtitleView(model: playerCoordinator.subtitleModel)
                        .allowsHitTesting(false) // 禁止字幕视图交互，以免抢占视图的点击事件或其它手势事件
                    Spacer()
                }
                .padding()
                controllerView(playerWidth: proxy.size.width)
                #if os(tvOS)
                    .ignoresSafeArea()
                #endif
                #if os(tvOS)
                if isDropdownShow {
                    VideoSettingView(model: videoSettingModel)
                        .focused($focusableField, equals: .info)
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
                if playerCoordinator.state.isPlaying {
                    playerCoordinator.playerLayer?.pause()
                } else {
                    playerCoordinator.playerLayer?.play()
                }
            }
            .onExitCommand {
                if playerCoordinator.isMaskShow {
                    playerCoordinator.isMaskShow = false
                } else {
                    switch focusableField {
                    case .play:
                        dismiss()
                    default:
                        focusableField = .play
                    }
                }
            }
        #endif
    }

    private var playView: some View {
        KSVideoPlayer(coordinator: playerCoordinator, url: url, options: options)
            .onStateChanged { playerLayer, state in
                if state == .readyToPlay {
                    if let movieTitle = playerLayer.player.dynamicInfo?.metadata["title"] {
                        title = movieTitle
                        // Keep the settings-sheet model's title in sync with the
                        // resolved media title (sheet's "Search Subtitle" reads model.title).
                        videoSettingModel.title = movieTitle
                    }
                }
            }
            .onBufferChanged { bufferedCount, consumeTime in
                print("bufferedCount \(bufferedCount), consumeTime \(consumeTime)")
            }
        #if canImport(UIKit)
            .onSwipe { _ in
                playerCoordinator.isMaskShow = true
            }
        #endif
            .ignoresSafeArea()
            .onAppear {
                focusableField = .play
                if let subtitleDataSource {
                    playerCoordinator.subtitleModel.addSubtitle(dataSource: subtitleDataSource)
                }
                // RE §18.3: lifecycle hook fires with `isAppearing = true` on appear.
                lifeCycleBlock?(playerCoordinator, true)
                // 不要加这个，不然playerCoordinator无法释放，也可以在onDisappear调用removeMonitor释放
                //                    #if os(macOS)
                //                    NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
                //                        isMaskShow = overView
                //                        return $0
                //                    }
                //                    #endif
            }
            .onDisappear {
                // RE §18.3: lifecycle hook fires with `isAppearing = false` on disappear.
                lifeCycleBlock?(playerCoordinator, false)
            }

        #if os(iOS) || os(xrOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(iOS)
            .focusable(!playerCoordinator.isMaskShow)
        .focused($focusableField, equals: .play)
        #endif
        #if !os(xrOS)
            .onKeyPressLeftArrow {
            playerCoordinator.skip(interval: -15)
        }
        .onKeyPressRightArrow {
            playerCoordinator.skip(interval: 15)
        }
        .onKeyPressSpace {
            if playerCoordinator.state.isPlaying {
                playerCoordinator.playerLayer?.pause()
            } else {
                playerCoordinator.playerLayer?.play()
            }
        }
        #endif
        #if os(macOS)
            .onTapGesture(count: 2) {
                guard let view = playerCoordinator.playerLayer?.player.view else {
                    return
                }
                view.window?.toggleFullScreen(nil)
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
        }
        .onExitCommand {
            playerCoordinator.playerLayer?.player.view?.exitFullScreenMode()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                playerCoordinator.skip(interval: -15)
            case .right:
                playerCoordinator.skip(interval: 15)
            case .up:
                playerCoordinator.playerLayer?.player.playbackVolume += 0.2
            case .down:
                playerCoordinator.playerLayer?.player.playbackVolume -= 0.2
            @unknown default:
                break
            }
        }
        #else
        .onTapGesture {
                playerCoordinator.isMaskShow.toggle()
            }
        #endif
        #if os(tvOS)
            .onMoveCommand { direction in
            switch direction {
            case .left:
                playerCoordinator.skip(interval: -15)
            case .right:
                playerCoordinator.skip(interval: 15)
            case .up:
                playerCoordinator.mask(show: true, autoHide: false)
            case .down:
                focusableField = .info
            @unknown default:
                break
            }
        }
        #else
        .onHover { _ in
                playerCoordinator.isMaskShow = true
            }
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers -> Bool in
                providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                    if let data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) {
                        openURL(url)
                    }
                }
                return true
            }
        #endif
    }

    private func controllerView(playerWidth: Double) -> some View {
        VStack {
            VideoControllerView(config: playerCoordinator, subtitleModel: playerCoordinator.subtitleModel, title: $title, volumeSliderSize: playerWidth / 4, videoSettingModel: videoSettingModel)
            #if !os(xrOS)
            // 设置opacity为0，还是会去更新View。所以只能这样了
            if playerCoordinator.isMaskShow {
                VideoTimeShowView(config: playerCoordinator, model: playerCoordinator.timemodel)
                    .onAppear {
                        focusableField = .controller
                    }
                    .onDisappear {
                        focusableField = .play
                    }
            }
            #endif
        }
        #if os(xrOS)
        .ornament(visibility: playerCoordinator.isMaskShow ? .visible : .hidden, attachmentAnchor: .scene(.bottom)) {
            ornamentView(playerWidth: playerWidth)
        }
        .sheet(isPresented: $showVideoSetting) {
            NavigationStack {
                VideoSettingView(model: videoSettingModel)
            }
            .buttonStyle(.plain)
        }
        #elseif os(tvOS)
        .padding(.horizontal, 80)
        .padding(.bottom, 80)
        .background(overlayGradient)
        #endif
        .focused($focusableField, equals: .controller)
        .opacity(playerCoordinator.isMaskShow ? 1 : 0)
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
            KSVideoPlayerViewBuilder.titleView(title: title, config: playerCoordinator)
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
            KSVideoPlayerViewBuilder.playbackControlView(config: playerCoordinator, spacing: 16)
            Spacer()
            VideoTimeShowView(config: playerCoordinator, model: playerCoordinator.timemodel, timeFont: .title3.monospacedDigit())
            Spacer()
            Group {
                KSVideoPlayerViewBuilder.contentModeButton(config: playerCoordinator)
                KSVideoPlayerViewBuilder.subtitleButton(config: playerCoordinator)
                KSVideoPlayerViewBuilder.playbackRateButton(playbackRate: $playerCoordinator.playbackRate)
                KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
            }
            .font(.largeTitle)
        }
    }

    fileprivate enum FocusableField {
        case play, controller, info
    }

    public func openURL(_ url: URL) {
        runOnMainThread {
            if url.isSubtitle {
                let info = URLSubtitleInfo(url: url)
                playerCoordinator.subtitleModel.selectedSubtitleInfo = info
            } else if url.isAudio || url.isMovie {
                self.url = url
                title = url.lastPathComponent
                // Mirror the new title into the settings-sheet model (see onStateChanged).
                videoSettingModel.title = url.lastPathComponent
            }
        }
    }
}

/// RE: doc §18.4 (KSCorePlayerView, 1.3.15). The 5-field core player view that wraps the
/// `KSVideoPlayer` UIView/NSView bridge with the system-overlay / toolbar / status-bar / drop
/// modifiers.
///
/// In the 1.3.15 binary SwiftUI inlined this struct's `body` into `KSVideoPlayerView.body`
/// (`FUN_1014a398c`) — no standalone `body` or View-conformance symbol was emitted; only its
/// `__swift5_fieldmd` field descriptor and `#file` string survive (doc §18.4, verified live).
/// Per the reconstruction rules ("Implement Everything, Scrap Later"), the named type is
/// materialized here as a real `View` with its documented 5-field roster and the inlined
/// modifier chain, rather than left as reflection-only metadata. `_config` is the
/// `ObservedObject<Coordinator>` lifted from the parent model's `config`.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct KSCorePlayerView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    fileprivate let url: URL
    fileprivate let options: KSOptions
    @Binding
    fileprivate var title: String
    fileprivate let subtitleDataSource: SubtitleDataSource?

    var body: some View {
        ZStack {
            KSVideoPlayer(coordinator: config, url: url, options: options)
                .onStateChanged { playerLayer, state in
                    if state == .readyToPlay {
                        if let movieTitle = playerLayer.player.dynamicInfo?.metadata["title"] {
                            title = movieTitle
                        }
                    }
                }
                .ignoresSafeArea()
                .onAppear {
                    if let subtitleDataSource {
                        config.subtitleModel.addSubtitle(dataSource: subtitleDataSource)
                    }
                }
        }
        // RE §18.4 inlined modifier chain (FUN_1014a398c): tap-to-toggle the mask, hide the
        // persistent system overlays, hide both the automatic and tab-bar toolbars, hide the
        // status bar, and accept dropped file URLs.
        .onTapGesture(count: 1) {
            config.isMaskShow.toggle()
        }
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .automatic)
        #if !os(macOS)
        // The .tabBar toolbar placement is UIKit-only (iOS/tvOS/visionOS).
        .toolbar(.hidden, for: .tabBar)
        #endif
        #if os(iOS) || os(xrOS)
        // statusBar(hidden:) exists only on iOS/visionOS (tvOS and macOS have no status bar).
        .statusBar(hidden: true)
        #endif
        #if !os(tvOS)
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers -> Bool in
            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                if let data, let path = NSString(data: data, encoding: 4), let dropped = URL(string: path as String) {
                    if dropped.isSubtitle {
                        config.subtitleModel.selectedSubtitleInfo = URLSubtitleInfo(url: dropped)
                    }
                }
            }
            return true
        }
        #endif
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

    func onKeyPressSpace(action: @escaping () -> Void) -> some View {
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

/// RE: 0x1014B7578 (VideoControllerView.body, 1.3.15). The transport/controls overlay
/// (close, AirPlay, audio, mute, content-mode, subtitle, playback-rate, PiP, info, and
/// — when a multi-URL playlist is loaded — previous/next playlist navigation), plus the
/// `.sheet`-presented `VideoSettingView`.
///
/// NOTE (model-vs-coordinator divergence): doc §18.7 records this view as observing a
/// `SwiftUI.ObservedObject<KSVideoPlayerModel>` (the RE binary's aggregating model).
/// This upstream form observes the `KSVideoPlayer.Coordinator` directly; the rendered
/// controls and behavior are equivalent. The playlist-navigation gate (doc reads
/// `KSVideoPlayerModel::urls.count >= 2`) is therefore expressed here against the
/// player layer's playlist surface — see `buildPlaylistNavigationControls`.
@available(iOS 16, tvOS 16, macOS 13, *)
struct VideoControllerView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var subtitleModel: SubtitleModel
    @Binding
    fileprivate var title: String
    fileprivate var volumeSliderSize: Double?
    /// Aggregating model the relocated §18.14 `VideoSettingView(model:)` consumes for
    /// this view's own info `.sheet`. Owned (as a `@StateObject`) by the parent
    /// `KSVideoPlayerView` and injected here so both sheets share one stable model whose
    /// `title` the parent keeps in sync.
    fileprivate var videoSettingModel: KSVideoPlayerModel
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
            buildPlaylistNavigationControls()
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
            VideoSettingView(model: videoSettingModel)
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
            config.playerLayer?.isPipActive.toggle()
        } label: {
            Image(systemName: "rectangle.on.rectangle.circle.fill")
        }
    }

    private var infoButton: some View {
        KSVideoPlayerViewBuilder.infoButton(showVideoSetting: $showVideoSetting)
    }

    /// RE: 0x1014BA354 (VideoControllerView.buildPlaylistNavigationControls, 1.3.15).
    /// Renders the central transport row flanked by previous/next playlist buttons. The two
    /// playlist buttons are gated on the layer carrying a multi-URL playlist (binary:
    /// `KSVideoPlayerModel::urls.count >= 2`, i.e. only emitted when the count is *not* < 2)
    /// and are styled with `.borderlessButtonStyle()`. Each action thunk reads
    /// `config.playerLayer`, dynamic-casts it to `KSPlayerLayer`, and advances the playlist:
    ///   - leading button  → 0x1014aec8c → `KSPlayerLayer.shuffleAndPlayNextURL` @ 0x1013b86f0
    ///   - trailing button → 0x1014aeebc → forward-advance vtable slot (+0x3c8)
    /// The shared label builder (0x1014aedc8 / 0x1014af00c) emits `Image(systemName:)` glyphs.
    ///
    /// CROSS-FILE NEEDED (KSPlayerLayer, proven via the action-thunk decompiles above):
    ///   * `var isPlaylist: Bool` (public) — proving site reads private `urls` (0x245) in
    ///     `buildPlaylistNavigationControls @ 0x1014BA354`; needed for the exact `count >= 2` gate.
    ///   * `func playNextURLInPlaylist()` must be made `public` (currently private @ 0x1013b77fc) —
    ///     it is the +0x3c8 forward-advance slot invoked by the trailing-button thunk 0x1014aeebc.
    /// Until that surface exists, both actions route through the one public advancer
    /// (`shuffleAndPlayNextURL`) and the gate uses the public proxy below.
    @MainActor
    @ViewBuilder
    private func buildPlaylistNavigationControls() -> some View {
        HStack {
            if hasPlaylistNavigation {
                Button {
                    config.playerLayer?.shuffleAndPlayNextURL()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.borderless)
            }
            KSVideoPlayerViewBuilder.playbackControlView(config: config)
            if hasPlaylistNavigation {
                Button {
                    config.playerLayer?.shuffleAndPlayNextURL()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Playlist-navigation gate. Binary reads `KSVideoPlayerModel::urls.count >= 2`
    /// (`buildPlaylistNavigationControls @ 0x1014BA354`). This upstream form observes the
    /// Coordinator (not the model) and the layer's `urls` array is private, so the exact
    /// count gate is a CROSS-FILE need (see `buildPlaylistNavigationControls` doc comment).
    // UNVERIFIED-GUESS: gating on `playerLayer != nil` as a proxy — the binary's true gate is
    // `KSPlayerLayer.urls.count >= 2`, which is unreachable here until `KSPlayerLayer.isPlaylist`
    // is exposed publicly (no binary anchor selects this proxy; it is a compilable placeholder).
    private var hasPlaylistNavigation: Bool {
        config.playerLayer != nil
    }
}

// NOTE: MenuView was relocated to PlatformView.swift (SwiftUIHelpers cluster, §18.18).
// The documented `selection` field is an OPTIONAL `Binding<Selection>?`; the moved
// definition reconciles that. Call sites here pass non-optional bindings, which Swift
// promotes to `.some(...)` automatically — no call-site change required.

/// RE: 0x1000853AC (VideoTimeShowView value-witness, 1.3.15). Drives the current/total time
/// labels from the `ControllerTimeModel` Published ints, styled by `timeFont`; renders a
/// scrubbable `Slider` when the player is seekable, otherwise a "Live Streaming" label.
/// Doc §18.8 field #3 records `timeFont` as a non-optional `SwiftUI.Font`; the default below
/// reproduces the binary's caption-style fallback while keeping the field non-optional.
@available(iOS 15, tvOS 15, macOS 12, *)
struct VideoTimeShowView: View {
    @ObservedObject
    fileprivate var config: KSVideoPlayer.Coordinator
    @ObservedObject
    fileprivate var model: ControllerTimeModel
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

// NOTE: VideoSubtitleView (the §18.15 subtitle-overlay view, plus its
// SubtitleLeftView / SubtitleRightView per-part surfaces) is owned by the
// SubtitleSystem cluster and lives in Subtitle/VideoSubtitleView.swift —
// reconstructed there from `VideoSubtitleView_buildSubtitleBody @ 0x10149C7D4`
// as the canonical single-field type (`_model :: ObservedObject<SubtitleModel>`,
// `init(model:)`). An earlier upstream copy of `VideoSubtitleView` (with a
// `static imageView(_:)` helper and a companion `private extension SubtitlePart`
// computing `subtitleView`) lived here; it was a stale same-module REDECLARATION
// of the SubtitleSystem-owned type and additionally called
// `LiveTextImage(uiImage:)`, which does not match `LiveTextImage`'s
// `init(cgImage:)`. The local copy and its `SubtitlePart` extension are removed;
// `KSVideoPlayerView.body` constructs the canonical type via
// `VideoSubtitleView(model: playerCoordinator.subtitleModel)` (see `body` above),
// whose `init(model:)` is the Subtitle/ version's designated initializer.

// NOTE: VideoSettingView (the §18.14 player-settings sheet) and its four nested
// content views (VideoView/AudioView/SubtitleView/InfoView), plus DynamicInfoView and
// HUDLogView, were relocated to VideoSettingView.swift (their designated §18.13/§18.14
// cluster home). An earlier upstream copy of a flat, 3-field `VideoSettingView`
// (config:subtitleModel:subtitleTitle:) lived here; it was a stale duplicate of the
// canonical 3-field type (_model/_dismiss/_selectedTab) and caused a same-module
// REDECLARATION build error. The local copy is removed; the canonical type's
// `init(model:)` is fed by the `videoSettingModel` @StateObject that `KSVideoPlayerView`
// owns (and `VideoControllerView` receives by injection) — a stable `KSVideoPlayerModel`
// wrapping the `KSVideoPlayer.Coordinator`, with its `title` mirrored from the view state.

// NOTE: PlatformView was relocated to PlatformView.swift (SwiftUIHelpers cluster, §18.18).

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct KSVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "http://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4")!
        KSVideoPlayerView(coordinator: KSVideoPlayer.Coordinator(), url: url, options: KSOptions())
    }
}
