//
//  KSVideoPlayerModel.swift
//  KSPlayer
//
//  Observable model for the SwiftUI video player. Aggregates a
//  KSVideoPlayer.Coordinator and re-publishes its changes, owning the
//  playlist (urls), the currently selected url, focus state, and the
//  video-setting sheet flag.
//
//  Binary: _TtC8KSPlayer18KSVideoPlayerModel (RE v1.3.15)
//

import Combine
import Foundation

public class KSVideoPlayerModel: ObservableObject {
    /// Focus target for the SwiftUI player surface.
    /// RE: KSVideoPlayerModel.FocusableView (ENUM_CASES_1.3.15) — distinct
    /// from KSVideoPlayerView.FocusableField (play/controller/info); this
    /// one is play/controller/slider.
    public enum FocusableView: Int {
        case play = 0
        case controller = 1
        case slider = 2
    }

    public var urls: [URL] = []

    @Published public var url: URL?
    @Published public var focusableView: FocusableView?
    @Published public var showVideoSetting: Bool = false
    @Published public var title: String = ""

    // RE: field #2 `config` — non-optional KSVideoPlayer.Coordinator
    // (NOT KSPlayerLayer.Coordinator). The init always assigns either the
    // passed Coordinator or a freshly allocated one, so it is never nil.
    // The decompile of init @0x1014AA20C writes this slot directly and
    // readers (resetFilters, the StateObject getter @0x1014A5878) read the
    // stored field directly — so `config` is a plain stored property with
    // no custom get/set or willSet/didSet.
    public var config: KSVideoPlayer.Coordinator
    public var options: KSOptions
    private var cancellables = Set<AnyCancellable>()

    // RE: KSVideoPlayerModel_init_title_coordinator_options @ 0x1014AA20C
    public init(title: String = "", coordinator: KSVideoPlayer.Coordinator? = nil, options: KSOptions) {
        // Documented defaults: urls = [], _url = nil, _focusableView = nil,
        // _showVideoSetting = false, cancellables = [], _title = passed title.
        self.urls = []
        self.url = nil
        self.focusableView = nil
        self.showVideoSetting = false
        self.title = title
        // config = passed Coordinator OR a freshly allocated one
        // (Coordinator_init_publishedProperties @0x1013BF9F8) if nil.
        self.config = coordinator ?? KSVideoPlayer.Coordinator()
        self.options = options

        // Re-publish whenever the aggregated Coordinator changes.
        // RE: subscribes self.objectWillChange to config.objectWillChange via
        // Publisher.sink(receiveValue:) → AnyCancellable.store(in:&cancellables).
        config.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        resetFilters()
    }

    // RE: KSVideoPlayerModel_resetFilters @ 0x1014A8ABC
    // Re-applies player filters by clearing them to defaults: the decompile
    // resets options.videoFilters and options.audioFilters to the empty-array
    // singleton (PTR___swiftEmptyArrayStorage). Both are [String] on KSOptions.
    public func resetFilters() {
        options.videoFilters = []
        options.audioFilters = []
    }
}
