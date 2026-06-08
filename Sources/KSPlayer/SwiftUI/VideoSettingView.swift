//
//  VideoSettingView.swift
//  KSPlayer
//
//  SwiftUI player-settings sheet family (KSPlayer OWN SwiftUI player layer,
//  doc §18.13 / §18.14). Designated cluster home for:
//    - VideoSettingView (+ ContentTab) — the 4-tab settings sheet
//    - VideoSettingView.VideoView / AudioView / SubtitleView / InfoView — tab content
//    - DynamicInfoView — live decode/render metrics (relocated from KSVideoPlayerView.swift)
//    - HUDLogView — scrolling log of the same DynamicInfo source
//
//  Binary: Components-adjacent KSPlayer SwiftUI surface, RE v1.3.15.
//

import Combine
import Foundation
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - VideoSettingView

/// RE: 0x1014BC660 (VideoSettingView_body_getter, 1.3.15).
///
/// The player-settings sheet. Doc §18.14 records exactly 3 stored fields:
///   1. `_model`       :: SwiftUI.ObservedObject<KSPlayer.KSVideoPlayerModel>
///   2. `_dismiss`     :: SwiftUI.Environment<SwiftUI.DismissAction>
///   3. `_selectedTab` :: SwiftUI.State<KSPlayer.VideoSettingView.ContentTab>
///
/// The body builds a segmented `Picker` bound to `_selectedTab`, then switches on
/// the tab raw value (`(byte) < 2` → Video/Subtitle, `== 2` → Audio, else → Info),
/// emitting one of the four nested content views via SwiftUI's `_ConditionalContent`
/// (produced here by the `@ViewBuilder` if/else ladder). When the model's
/// `config.playerLayer` is nil it shows a localized "Loading..." Text
/// (string literal 0x2e676e6964616f4c = "Loading.").
@available(iOS 16, tvOS 16, macOS 13, *)
struct VideoSettingView: View {
    /// Doc field #1 — the single ObservedObject driving the sheet. The body's
    /// `model.config.playerLayer` access path resolves through this model's
    /// `KSVideoPlayer.Coordinator` (`config`).
    @ObservedObject
    fileprivate var model: KSVideoPlayerModel

    /// Doc field #2 — dismiss action (carried over verbatim from the prior type).
    @Environment(\.dismiss)
    private var dismiss

    /// Doc field #3 — selected segmented tab, defaults to `.Video` (raw 0).
    @State
    private var selectedTab: ContentTab = .Video

    /// Nested segmented-tab enum. RE: ENUM_CASES_1.3.15 (doc §18.6 / §18.14).
    /// Capitalized case names are preserved from the binary; explicit Int raw
    /// values back both the segmented `Picker` and the `(byte) < 2 / == 2 / else`
    /// switch in the body getter.
    enum ContentTab: Int, CaseIterable, Identifiable {
        case Video = 0
        case Subtitle = 1
        case Audio = 2
        case Info = 3

        var id: Int { rawValue }

        /// Localized segment label (used by the body's Picker).
        var title: LocalizedStringKey {
            switch self {
            case .Video: return "Video"
            case .Subtitle: return "Subtitle"
            case .Audio: return "Audio"
            case .Info: return "Info"
            }
        }
    }

    var body: some View {
        // Gate: the binary shows a localized "Loading." Text until the layer exists.
        if let playerLayer = model.config.playerLayer {
            PlatformView {
                // Segmented tab selector bound to `_selectedTab`.
                Picker("", selection: $selectedTab) {
                    ForEach(ContentTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                // Switch on the tab raw value, exactly mirroring the binary's
                // `(byte) < 2` / `== 2` / else dispatch. The if/else ladder lowers
                // to nested `_ConditionalContent` as in the decompile.
                if selectedTab.rawValue < 2 {
                    if selectedTab == .Video {
                        VideoView(model: model, playerLayer: playerLayer)
                    } else {
                        SubtitleView(model: model, playerLayer: playerLayer)
                    }
                } else if selectedTab == .Audio {
                    AudioView(model: model, playerLayer: playerLayer)
                } else {
                    InfoView(playerLayer: playerLayer)
                }
            }
            #if os(macOS) || targetEnvironment(macCatalyst) || os(xrOS)
            // macOS/Catalyst/visionOS surface the dismiss affordance in the toolbar;
            // iOS/tvOS dismiss via the sheet's own chrome. Rationale: AppKit sheets
            // have no swipe-to-dismiss, so an explicit Done button is required.
            .toolbar {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            #endif
        } else {
            // String literal 0x2e676e6964616f4c = "Loading.".
            Text("Loading...")
        }
    }
}

// MARK: - VideoSettingView nested content views

@available(iOS 16, tvOS 16, macOS 13, *)
extension VideoSettingView {
    /// RE: 0x1014CA978 ($s8KSPlayer16VideoSettingViewV9VideoViewVwca, 1.3.15).
    ///
    /// Video tab (tab value 0). Doc §18.14 records two fields:
    ///   - `model`       :: KSVideoPlayerModel   (stored directly — NOT @ObservedObject)
    ///   - `playerLayer` :: KSPlayerLayer
    /// Renders the video-track picker and the resolved dynamic-range type.
    struct VideoView: View {
        // Stored directly per the doc field roster (no property wrapper for this one).
        let model: KSVideoPlayerModel
        let playerLayer: KSPlayerLayer

        var body: some View {
            let videoTracks = playerLayer.player.tracks(mediaType: .video)
            if !videoTracks.isEmpty {
                Picker(selection: Binding {
                    videoTracks.first { $0.isEnabled }?.trackID
                } set: { value in
                    if let track = videoTracks.first(where: { $0.trackID == value }) {
                        playerLayer.player.select(track: track)
                    }
                }) {
                    ForEach(videoTracks, id: \.trackID) { track in
                        Text(track.description).tag(track.trackID as Int32?)
                    }
                } label: {
                    Label("Video Track", systemImage: "video.fill")
                }
                LabeledContent("Video Type", value: (videoTracks.first { $0.isEnabled }?.dynamicRange ?? .sdr).description)
                LabeledContent("Stream Type", value: (videoTracks.first { $0.isEnabled }?.fieldOrder ?? .progressive).description)
            }
        }
    }

    /// RE: 0x1014CA6F8 ($s8KSPlayer16VideoSettingViewV9AudioViewVwca, 1.3.15).
    ///
    /// Audio tab (tab value 2). Doc §18.14 records two fields:
    ///   - `_model`      :: ObservedObject<KSVideoPlayerModel>
    ///   - `playerLayer` :: KSPlayerLayer
    /// Renders the audio-track picker. Atmos constraint: track selection routes
    /// through `playerLayer.player.select(track:)` (AVPlayer-backed), never through
    /// a separate audio engine.
    struct AudioView: View {
        @ObservedObject
        var model: KSVideoPlayerModel
        let playerLayer: KSPlayerLayer

        var body: some View {
            let audioTracks = playerLayer.player.tracks(mediaType: .audio)
            if !audioTracks.isEmpty {
                Picker(selection: Binding {
                    audioTracks.first { $0.isEnabled }?.trackID
                } set: { value in
                    if let track = audioTracks.first(where: { $0.trackID == value }) {
                        playerLayer.player.select(track: track)
                    }
                }) {
                    ForEach(audioTracks, id: \.trackID) { track in
                        Text(track.description).tag(track.trackID as Int32?)
                    }
                } label: {
                    Label("Audio Track", systemImage: "waveform")
                }
            }
        }
    }

    /// RE: 0x1014CA834 ($s8KSPlayer16VideoSettingViewV12SubtitleViewVwca, 1.3.15).
    ///
    /// Subtitle tab (tab value 1). Doc §18.14 records exactly three fields:
    ///   - `_model`              :: ObservedObject<KSVideoPlayerModel>
    ///   - `playerLayer`         :: KSPlayerLayer
    ///   - `_subtitleFileImport` :: State<Bool>   (drives the file-import sheet/toggle)
    /// Renders the subtitle-track picker, delay/title fields, an online-search
    /// button, and a "load subtitle file" affordance backed by `_subtitleFileImport`.
    ///
    /// Note: the online-search query is sourced from `model.title` (the
    /// `@Published title` already on `KSVideoPlayerModel`), NOT a separate stored
    /// `@State`. The pre-relocation flat `VideoSettingView` needed its own
    /// `subtitleTitle` field only because it bound `SubtitleModel`/`Coordinator`
    /// directly without a `KSVideoPlayerModel`; the documented 3-field roster has
    /// no such field, so the title binding is routed through the model here.
    struct SubtitleView: View {
        @ObservedObject
        var model: KSVideoPlayerModel
        let playerLayer: KSPlayerLayer

        /// State<Bool> from the doc — presents the subtitle file importer.
        @State
        private var subtitleFileImport: Bool = false

        var body: some View {
            let subtitleModel = model.config.subtitleModel
            Picker(selection: Binding {
                subtitleModel.selectedSubtitleInfo?.subtitleID
            } set: { value in
                subtitleModel.selectedSubtitleInfo = subtitleModel.subtitleInfos.first { $0.subtitleID == value }
            }) {
                Text("Off").tag(String?.none)
                ForEach(subtitleModel.subtitleInfos, id: \.subtitleID) { info in
                    Text(info.name).tag(info.subtitleID as String?)
                }
            } label: {
                Label("Subtitle Track", systemImage: "captions.bubble")
            }
            TextField("Subtitle delay", value: $subtitleModel.subtitleDelay, format: .number)
            // Title query seeded from the model's own `@Published title` field.
            TextField("Title", text: $model.title)
            Button("Search Subtitle") {
                subtitleModel.searchSubtitle(query: model.title, languages: ["zh-cn"])
            }
            #if !os(tvOS)
            // tvOS has no document browser, so the file-import affordance is
            // limited to platforms with `fileImporter` document-picker support.
            Button("Load Subtitle File") {
                subtitleFileImport = true
            }
            .fileImporter(isPresented: $subtitleFileImport, allowedContentTypes: subtitleFileTypes) { result in
                guard let url = try? result.get() else {
                    return
                }
                // File-backed subtitle: wrap the URL and register it on the model.
                subtitleModel.addSubtitle(info: URLSubtitleInfo(url: url))
            }
            #endif
        }

        /// Allowed content types for the subtitle file importer. `.data` is the
        /// permissive fallback the engine uses elsewhere (FilesView) since subtitle
        /// container UTIs (srt/ass/vtt) are not all system-declared.
        private var subtitleFileTypes: [UTType] {
            [.plainText, .data]
        }
    }

    /// RE: 0x1014BC660 (VideoSettingView body getter else-branch, 1.3.15).
    ///
    /// Info tab (tab value 3). Doc §18.14 records a single field:
    ///   - `playerLayer` :: KSPlayerLayer   (no model)
    /// The metrics/info pane: embeds the live `DynamicInfoView`, the scrolling
    /// `HUDLogView`, and the file-size readout, all sourced from
    /// `playerLayer.player`.
    struct InfoView: View {
        let playerLayer: KSPlayerLayer

        var body: some View {
            if let dynamicInfo = playerLayer.player.dynamicInfo {
                DynamicInfoView(dynamicInfo: dynamicInfo)
                HUDLogView(dynamicInfo: dynamicInfo)
            }
            let fileSize = playerLayer.player.fileSize
            if fileSize > 0 {
                LabeledContent("File Size", value: fileSize.kmFormatted + "B")
            }
        }
    }
}

// MARK: - DynamicInfoView

/// RE: 0x1014C6BA0 (DynamicInfoView_projectedValue_getter / $dynamicInfo, 1.3.15).
///
/// Doc §18.13: SwiftUI View struct with a single field
/// `_dynamicInfo :: ObservedObject<KSPlayer.DynamicInfo>`. Renders the live
/// decode/render metrics (FPS, A/V sync, dropped frames, bytes read, bitrates).
/// The `$dynamicInfo` projected-value accessor at 0x1014C6BA0 is synthesized by
/// the `@ObservedObject` wrapper.
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

// MARK: - HUDLogView

/// RE: no named function (1.3.15) — `search_functions("HUDLogView")` returns none
/// per doc §18.13; the body is inlined, so this type is reconstructed from its
/// `types.json` field roster and documented role rather than a code address.
/// (0x1014C6BA0 is `DynamicInfoView`'s `$dynamicInfo` projected-value accessor, a
/// sibling type — not an anchor for `HUDLogView`, so it is deliberately not cited.)
///
/// Doc §18.13: SwiftUI View struct with a single field
/// `_dynamicInfo :: ObservedObject<KSPlayer.DynamicInfo>` — the same on-screen HUD
/// metrics model that `DynamicInfoView` renders as live values. `HUDLogView`
/// renders the *scrolling log* of that source.
@available(iOS 16, tvOS 16, macOS 13, *)
public struct HUDLogView: View {
    @ObservedObject
    fileprivate var dynamicInfo: DynamicInfo

    public var body: some View {
        // Scrolling log of the DynamicInfo metadata stream. `metadata` is the
        // key/value dictionary the player publishes (container/stream tags);
        // rendered as a fixed-height scroll so the pane never grows unbounded.
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(dynamicInfo.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("\(key): \(value)")
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: 160)
    }
}
