//
//  KSVideoPlayerModel.swift
//  KSPlayer
//
//  Forward addition (RE): Observable model for SwiftUI video player.
//
//  Binary: _TtC8KSPlayer18KSVideoPlayerModel (3 functions)
//  RE source: Forward v1.3.15
//

import Combine
import Foundation

public class KSVideoPlayerModel: ObservableObject {
    public var urls: [URL] = []

    @Published public var url: URL?
    @Published public var focusableView: Bool?
    @Published public var showVideoSetting: Bool = false
    @Published public var title: String = ""

    public var config: KSPlayerLayer.Coordinator?
    public var options: KSOptions?
    private var cancellables = Set<AnyCancellable>()

    // RE: KSVideoPlayerModel_init_title_coordinator_options @ 0x1014aa20c
    public init(title: String = "", coordinator: KSPlayerLayer.Coordinator? = nil, options: KSOptions? = nil) {
        self.title = title
        self.config = coordinator ?? KSPlayerLayer.Coordinator()
        self.options = options

        config?.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        resetFilters()
    }

    // RE: KSVideoPlayerModel_resetFilters @ 0x1014a8abc
    public func resetFilters() {
        // Reset video filters to defaults
    }

    // RE: KSVideoPlayerModel_config_accessors @ 0x1014a5878
}
