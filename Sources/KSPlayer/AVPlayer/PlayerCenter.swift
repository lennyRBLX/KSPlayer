//
//  PlayerCenter.swift
//  KSPlayer
//
//  App-layer session management — presenting/dismissing player, managing the
//  `enhanceDolby` toggle and PiP state. See `.reversal/DolbyVision.md
//  §"Lifecycle write sites for DAT_104450978"` for the binary's behaviour.
//

import Combine
import Foundation

/// Centralized player session manager.
/// Coordinates player presentation lifecycle and the `enhanceDolby` flag
/// that gates the Dolby Vision decode path.
@MainActor
public final class PlayerCenter: ObservableObject {
    /// Shared singleton instance for app-wide player session management.
    public static let shared = PlayerCenter()

    @Published public var isPlayerPresented = false
    @Published public var isPipActive = false

    public private(set) var currentURL: URL?
    public private(set) var currentOptions: KSOptions?

    public init() {}

    /// Present the player with a URL and optional configuration. Force-enables
    /// `enhanceDolby` on entry to match the binary's lifecycle behaviour.
    ///
    /// **Binary cross-reference** (`.reversal/DolbyVision.md §"Lifecycle write sites"`):
    /// - Function entry: `PlayerCenter_presentPlayerViewController @ 0x101027cd0`
    /// - Write site: `DAT_104450978 = 1` at instruction `0x101027fec`
    /// - The binary write is an unconditional constant store and skips
    ///   `_swift_beginAccess`. It is paired with an `NSUserDefaults
    ///   setBool:forKey:` call that mirrors the new value into the persisted
    ///   defaults. Net effect: the user's `PlayerPreferences.enhanceDolby` is
    ///   overridden on every player launch.
    /// - This Swift port reproduces the observable behaviour idiomatically via
    ///   `@AppStorage("enhance_dolby")` in `PlayerPreferences` plus the
    ///   `KSOptions.enhanceDolby = true` assignment below.
    ///
    /// - Parameters:
    ///   - url: The media URL to play.
    ///   - options: Player configuration. Defaults to a fresh `KSOptions` if nil.
    public func present(url: URL, options: KSOptions? = nil) {
        currentURL = url
        currentOptions = options ?? KSOptions()
        KSOptions.enhanceDolby = true
        isPlayerPresented = true
    }

    /// Dismiss the player and reset session state. Force-disables `enhanceDolby`
    /// unless PiP is still active, matching the binary's lifecycle write.
    ///
    /// **Binary cross-reference** (`.reversal/DolbyVision.md §"Lifecycle write sites"`):
    /// - Function entry: `PlayerCenter_dismissPlayer @ 0x100fcc540`
    /// - Write site: `DAT_104450978 = 0` at instruction `0x100fcc6e4`
    /// - Same unconditional, `_swift_beginAccess`-bypassing pattern as
    ///   `presentPlayerViewController`; also mirrors the value into
    ///   `NSUserDefaults`.
    public func dismiss() {
        isPlayerPresented = false
        if !isPipActive {
            KSOptions.enhanceDolby = false
        }
        currentURL = nil
        currentOptions = nil
    }

    /// Handle PiP state transitions. When PiP activates, `enhanceDolby` stays
    /// `true` to maintain DV decode; when PiP deactivates with the player
    /// already dismissed, `enhanceDolby` is cleared.
    ///
    /// **Binary cross-reference** (`.reversal/DolbyVision.md §"enhanceDolby
    /// Binding Chain"` + §"Statics that look related to enhanceDolby"):
    /// `PlayerCenter_checkEnhanceDolbyPiP @ 0x1000be458` reads `DAT_104450978`
    /// under `_swift_beginAccess`. The gated PiP body runs **only when
    /// `enhanceDolby == false`** -- i.e. PiP-related window message delivery is
    /// suppressed while the enhanced DV pipeline is on. This Swift port keeps
    /// `enhanceDolby` enabled across the PiP-active window precisely because
    /// the DV pipeline must remain selected for the PiP frame source.
    ///
    /// - Parameter isActive: Whether PiP is now active.
    public func handlePipStateChange(isActive: Bool) {
        isPipActive = isActive
        if !isActive, !isPlayerPresented {
            // PiP ended and player is already dismissed — safe to disable DV path.
            KSOptions.enhanceDolby = false
        }
    }
}
