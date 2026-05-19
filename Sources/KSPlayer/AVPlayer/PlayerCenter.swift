//
//  PlayerCenter.swift
//  KSPlayer
//
//  App-layer session management — presenting/dismissing player,
//  managing enhanceDolby toggle and PiP state.
//  Binary address: 0x100f6c474
//

import Combine
import Foundation

/// Centralized player session manager.
/// Coordinates player presentation lifecycle and the `enhanceDolby` flag
/// that gates the ProAVPlayer Dolby Vision decode path.
@MainActor
public final class PlayerCenter: ObservableObject {
    /// Shared singleton instance for app-wide player session management.
    /// RE: PlayerCenter uses a shared instance pattern for coordinating
    /// enhanceDolby state across player presentation and PiP lifecycle.
    public static let shared = PlayerCenter()

    @Published public var isPlayerPresented = false
    @Published public var isPipActive = false

    public private(set) var currentURL: URL?
    public private(set) var currentOptions: KSOptions?

    public init() {}

    /// Present the player with a URL and optional configuration.
    /// Sets `enhanceDolby = true` to enable the DV-enhanced decode path.
    /// RE: PlayerCenter_presentPlayerViewController at 0x101027fec
    ///
    /// - Parameters:
    ///   - url: The media URL to play.
    ///   - options: Player configuration. Defaults to a fresh KSOptions if nil.
    public func present(url: URL, options: KSOptions? = nil) {
        currentURL = url
        currentOptions = options ?? KSOptions()
        KSOptions.enhanceDolby = true
        isPlayerPresented = true
    }

    /// Dismiss the player and reset session state.
    /// Clears `enhanceDolby` unless PiP is still active.
    /// RE: PlayerCenter_dismissPlayer at 0x100fcc540
    public func dismiss() {
        isPlayerPresented = false
        if !isPipActive {
            KSOptions.enhanceDolby = false
        }
        currentURL = nil
        currentOptions = nil
    }

    /// Handle PiP state transitions.
    /// When PiP activates, enhanceDolby stays true to maintain DV decode.
    /// When PiP deactivates and the player is already dismissed, clear enhanceDolby.
    /// RE: PlayerCenter_checkEnhanceDolbyPiP at 0x1000be458
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
