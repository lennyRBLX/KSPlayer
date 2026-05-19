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
    /// Override to create DoviDisplayModel when DV content detected.
    /// RE: PlayerOptions_onVideoTrackOpened at 0x1008E3CF8
    ///
    /// When isDovi is true and enhanceDolby is false (Metal path),
    /// the display model should be DoviDisplayModel instead of PlaneDisplayModel.
    @MainActor
    open override func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription?) {
        super.updateVideo(refreshRate: refreshRate, isDovi: isDovi, formatDescription: formatDescription)
        if isDovi, !KSOptions.enhanceDolby {
            // Metal DV path: DoviDisplayModel is used instead of PlaneDisplayModel.
            // The display model switch is handled by MetalRender when it detects
            // DOVI side data on the frame. This hook allows subclasses to perform
            // additional configuration when DV content is first detected.
            KSLog("[PlayerOptions] DV content detected, Metal path active")
        }
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
        // This is used when the user explicitly picks a track from the UI.
        // Subclasses can override to inject a preferAudioId check here.

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
