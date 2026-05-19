//
//  AVMediaSelectionTrack.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — AVMediaSelectionOption-based track wrapper
//  for HLS subtitle/audio tracks surfaced via AVMediaSelectionGroup.
//

import AVFoundation

public class AVMediaSelectionTrack: MediaPlayerTrack {
    public let option: AVMediaSelectionOption
    public let group: AVMediaSelectionGroup
    public weak var playerItem: AVPlayerItem?

    // MARK: - MediaPlayerTrack conformance

    public var trackID: Int32
    public var name: String
    public var languageCode: String?
    public let mediaType: AVFoundation.AVMediaType
    public var nominalFrameRate: Float = 0
    public var bitRate: Int64 { 0 }
    public var bitDepth: Int32 { 0 }
    public var isImageSubtitle: Bool { false }
    public var rotation: Int16 { 0 }
    public var dovi: DOVIDecoderConfigurationRecord? { nil }
    public var fieldOrder: FFmpegFieldOrder { .unknown }
    public var formatDescription: CMFormatDescription? { nil }

    public var isEnabled: Bool {
        get {
            guard let playerItem else { return false }
            return playerItem.currentMediaSelection.selectedMediaOption(in: group) == option
        }
        set {
            guard let playerItem else { return }
            if newValue {
                playerItem.select(option, in: group)
            } else {
                // Deselect by choosing nil if allowed
                if group.allowsEmptySelection {
                    playerItem.select(nil, in: group)
                }
            }
        }
    }

    public var description: String {
        "\(name) [\(mediaType.rawValue)] lang=\(languageCode ?? "nil")"
    }

    public init(option: AVMediaSelectionOption, group: AVMediaSelectionGroup, playerItem: AVPlayerItem?) {
        self.option = option
        self.group = group
        self.playerItem = playerItem
        self.name = option.displayName
        self.languageCode = option.extendedLanguageTag
        self.mediaType = group.defaultOption?.mediaType ?? .subtitle
        self.trackID = Int32(option.hash & 0x7FFF_FFFF)
    }
}
