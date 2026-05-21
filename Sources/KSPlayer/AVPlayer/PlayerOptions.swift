//
//  PlayerOptions.swift
//  KSPlayer
//
//  Forward v1.3.15 binary-derived classes for Play app expansion.
//  Binary address: PlayerOptions at 0x1008e86c8
//

import AVFoundation
import Foundation

/// KSOptions subclass that bridges user preferences to player configuration.
/// Provides audio track selection cascade and Dolby Vision display model routing.
open class PlayerOptions: KSOptions {
    /// Preferred audio track ID for explicit user selection.
    /// RE: Forward v1.3.15 PlayerOptions field at preferAudioId getter vtable 0x10094debc.
    /// When set, takes highest priority in the wantedAudioTrack cascade (tier 1).
    public var preferAudioId: Int32?

    /// Hook fired when the video track is opened (or refresh-rate / format-description changes).
    ///
    /// RE references (v1.3.15 Ghidra):
    ///   PlayerOptions_onVideoTrackOpened_sync  @ 0x10094da8c
    ///   PlayerOptions_onVideoTrackOpened_async @ 0x10094ec8c
    /// (v1.3.14 IDA used 0x1008E3CF8 / 0x1008E4E5C; both are dead in v1.3.15.)
    ///
    /// `isDovi && !enhanceDolby` selects the in-process Metal `DoviDisplayModel` path; the
    /// active swap is performed in `MetalPlayView.draw` via the `doviMetadata` parameter
    /// (not via `KSOptions.display = .dovi` -- there is no `.dovi` case in `DisplayEnum`).
    /// The inverted `enhanceDolby` semantics vs. the Forward binary are documented on
    /// `KSOptions.enhanceDolby` and in `MetalPlayView.draw`.
    @MainActor
    open override func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription?) {
        super.updateVideo(refreshRate: refreshRate, isDovi: isDovi, formatDescription: formatDescription)
        if isDovi, !KSOptions.enhanceDolby {
            KSLog("[PlayerOptions] DV content detected, Metal DoviDisplayModel path active")
        }
    }

    /// Override wantedAudio to use the 4-tier wantedAudioTrack cascade.
    /// RE: PlayerOptions_wantedAudioTrack wired as backing implementation for wantedAudio.
    open override func wantedAudio(tracks: [MediaPlayerTrack]) -> Int? {
        guard let selected = wantedAudioTrack(from: tracks) else { return nil }
        return tracks.firstIndex(where: { $0.trackID == selected.trackID })
    }

    /// 4-tier audio track selection cascade.
    /// RE: PlayerOptions_wantedAudioTrack at 0x100923EA4 (~3072 bytes)
    /// Priority: preferAudioId > videoPreference language > AppStorage language pref > system locale
    ///
    /// - Parameters:
    ///   - tracks: Available audio tracks from the media source.
    ///   - preferredLanguage: Optional language code override (e.g. from AppStorage preference).
    /// - Returns: The best matching audio track, or nil if no tracks available.
    open func wantedAudioTrack(from tracks: [any MediaPlayerTrack], preferredLanguage: String? = nil) -> (any MediaPlayerTrack)? {
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        guard !audioTracks.isEmpty else { return nil }

        // Tier 1: If a specific track ID is preferred (set externally), select it directly.
        // RE: Binary at 0x10094debc — preferAudioId getter feeds into wantedAudioTrack as param_3.
        // The binary loops tracks comparing trackID description strings against preferAudioId.
        if let preferAudioId {
            if let match = audioTracks.first(where: { $0.trackID == preferAudioId }) {
                return match
            }
        }

        // Tier 2: Match by user's preferred language (from AppStorage or parameter).
        if let preferredLanguage, !preferredLanguage.isEmpty {
            if let match = audioTracks.first(where: { $0.languageCode == preferredLanguage }) {
                return match
            }
        }

        // Tier 3: Match by system locale language.
        let systemLanguage = Locale.current.language.languageCode?.identifier
        if let systemLanguage {
            if let match = audioTracks.first(where: { $0.languageCode == systemLanguage }) {
                return match
            }
        }

        // Tier 4: Fall back to first audio track.
        return audioTracks.first
    }
}

/// KSOptions subclass for background trailer autoplay.
/// Configured for silent, looping playback suitable for home screen banners.
/// Binary init at 0x1008E4CB0 (428 bytes).
public final class TrailerPlayerOptions: KSOptions {
    public override init() {
        super.init()
        // RE: trailer player disables auto-play (caller controls start),
        // enables loop for continuous background playback.
        isLoopPlay = true
        canStartPictureInPictureAutomaticallyFromInline = false
        formatContextOptions["reconnect"] = 1
        // RE: videoInterlacingType = .undetermined (non-standard interlacing bypass),
        // audio is muted at the player level, mix audio session to avoid
        // interrupting other audio sources.
        videoInterlacingType = .undetermined
    }
}

// MARK: - VideoCoverViewModel

/// Manages trailer playback lifecycle for home screen banners.
/// Handles muted autoplay of trailer URLs with play/pause/reset lifecycle.
@MainActor
public final class VideoCoverViewModel: ObservableObject {
    @Published public var isPlaying = false
    @Published public var isMuted = true

    public private(set) var player: (any MediaPlayerProtocol)?
    private var trailerURL: URL?

    public init() {}

    /// Load a trailer URL and prepare the player for playback.
    /// - Parameter url: The trailer media URL.
    public func loadTrailer(from url: URL) {
        // Reset any existing player state
        reset()
        trailerURL = url
        let options = TrailerPlayerOptions()
        let playerType = KSOptions.firstPlayerType
        let newPlayer = playerType.init(url: url, options: options)
        newPlayer.isMuted = isMuted
        player = newPlayer
        newPlayer.prepareToPlay()
    }

    /// RE: playTrailer — entry point for media ID changes.
    /// Validates the URL, loads and starts the trailer player.
    /// Wire from Combine publisher on media ID change or metadata load.
    public func playTrailer(url: URL?) {
        guard let url, !url.absoluteString.isEmpty else {
            resetTrailer()
            return
        }
        loadTrailer(from: url)
        play()
    }

    /// RE: resetTrailer — tear down on validation failure, navigation away,
    /// content change, or error conditions.
    public func resetTrailer() {
        reset()
    }

    /// Start trailer playback.
    public func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    /// Pause trailer playback.
    public func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
    }

    /// Toggle mute state on the current player.
    public func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    /// Tear down the player and reset all state.
    public func reset() {
        player?.shutdown()
        player = nil
        trailerURL = nil
        isPlaying = false
    }
}
