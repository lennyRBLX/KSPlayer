//
//  KSComplexPlayerLayer.swift
//  KSPlayer
//
//  Forward addition (RE): KSPlayerLayer subclass adding PiP overlay
//  and remote command center integration.
//
//  Binary: _TtC8KSPlayer20KSComplexPlayerLayer (21 functions)
//  RE source: Forward v1.3.15
//

import AVKit
import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif

open class KSComplexPlayerLayer: KSPlayerLayer {
    public var urls: [URL] = []
    public var isPictureInPictureStoped: Bool = true

    private weak var pipController: AVPictureInPictureController?

    // MARK: - Init (RE: KSComplexPlayerLayer_initWithURL_options_delegate @ 0x1013b5298)

    public convenience init(url: URL, options: KSOptions, delegate: KSPlayerLayerDelegate?) {
        self.init()
        self.urls = [url]
        self.isPictureInPictureStoped = true
        set(url: url, options: options)
        self.delegate = delegate
        if options.registerRemoteControll {
            registerRemoteCommandHandlers()
        }
    }

    // MARK: - Init with MEPlayerItem (RE: KSComplexPlayerLayer_initWithMEPlayerItem_setupRemoteCommands @ 0x1013b61c8)

    public func setupWithMEPlayerItem(options: KSOptions) {
        if options.registerRemoteControll {
            registerRemoteCommandHandlers()
        }
        setupSubtitleAndPipDelegate()
    }

    // MARK: - Player Ready (RE: KSComplexPlayerLayer_onPlayerReady_setupAll @ 0x1013b2624)

    func onPlayerReadySetupAll() {
        maybeCreatePipController()
        setupSubtitleAndPipDelegate()
    }

    // MARK: - PiP (RE: KSComplexPlayerLayer_maybeCreatePipController @ 0x1013b6e38)

    func maybeCreatePipController() {
        #if canImport(UIKit) && !os(xrOS)
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if let playerView = player?.view as? UIView,
           let sampleBufferLayer = playerView.layer.sublayers?.first(where: { $0 is AVSampleBufferDisplayLayer }) as? AVSampleBufferDisplayLayer {
            let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: sampleBufferLayer, playbackDelegate: self)
            let pip = AVPictureInPictureController(contentSource: contentSource)
            pip.delegate = self
            self.pipController = pip
        }
        #endif
    }

    // MARK: - PiP Lifecycle (RE: 0x1013b6cc8, 0x1013b6d7c, 0x1013b6ab4)

    func pipWillStop() {
        isPictureInPictureStoped = true
    }

    func pipDidStop() {
        isPictureInPictureStoped = true
        postPiPStopCleanup()
        // RE: checkEnhanceDolbyPiP — notify PlayerCenter that PiP has stopped
        Task { @MainActor in
            PlayerCenter.shared.handlePipStateChange(isActive: false)
        }
    }

    func pipFailedToStart() {
        isPictureInPictureStoped = true
    }

    // MARK: - PiP Restore (RE: KSComplexPlayerLayer_restoreFromPiP @ 0x1013b6920)

    func restoreFromPiP() {
        isPictureInPictureStoped = false
        // RE: checkEnhanceDolbyPiP — notify PlayerCenter that PiP is active
        Task { @MainActor in
            PlayerCenter.shared.handlePipStateChange(isActive: true)
        }
    }

    // MARK: - PiP Restore Callback (RE: KSComplexPlayerLayer_pipRestoreCallback @ 0x1000357f0)

    func pipRestoreCallback(completionHandler: @escaping (Bool) -> Void) {
        restoreFromPiP()
        completionHandler(true)
    }

    // MARK: - Auto PiP Restart (RE: KSComplexPlayerLayer_autoPiPRestart_block @ 0x1013b822c)

    func autoPiPRestart() {
        guard !isPictureInPictureStoped else { return }
        pipController?.startPictureInPicture()
    }

    // MARK: - Post PiP Cleanup (RE: KSComplexPlayerLayer_postPiPStop_cleanup @ 0x1013b7bbc)

    private func postPiPStopCleanup() {
        // Clean up after PiP session ends
    }

    // MARK: - Player Ready PiP Setup (RE: KSComplexPlayerLayer_playerReady_setupPiP @ 0x1013b65a0)

    func playerReadySetupPiP() {
        maybeCreatePipController()
    }

    // MARK: - Init Setup PiP Restore (RE: KSComplexPlayerLayer_init_setupPiPRestore @ 0x1013b64b0)

    func setupPiPRestore() {
        isPictureInPictureStoped = true
    }

    // MARK: - Subtitle and PiP Delegate (RE: KSComplexPlayerLayer_setupSubtitleAndPipDelegate @ 0x1013b6f48)

    func setupSubtitleAndPipDelegate() {
        // Wire up PiP controller delegate and subtitle rendering delegate
        #if canImport(UIKit) && !os(xrOS)
        if #available(tvOS 14.0, *) {
            pipController?.delegate = self
            // Connect subtitle delegate from the player layer's pipSubtitleProvider
            if let subtitleProvider = pipSubtitleProvider as? KSPipSubtitleDelegate,
               let pip = player.pipController {
                pip.subtitleDelegate = subtitleProvider
            }
        }
        #endif
    }

    // MARK: - PiP Delegate Dispatch (RE: KSComplexPlayerLayer_pipDelegateDispatch_MainActor @ 0x1013b8144)

    func pipDelegateDispatchMainActor(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    // MARK: - Remote Commands (RE: KSComplexPlayerLayer_allocateAndInit_MEPlayerItem @ 0x1013af3b0)

    private func registerRemoteCommandHandlers() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            if self?.player?.isPlaying == true {
                self?.pause()
            } else {
                self?.play()
            }
            return .success
        }
    }

    // MARK: - Player Ready Hook (RE: wire onPlayerReadySetupAll from KSPlayerLayer.readyToPlay)

    open override func onPlayerReady() {
        onPlayerReadySetupAll()
    }

    // MARK: - Deinit (RE: KSComplexPlayerLayer_deinit_cleanup @ 0x1013b43d0)

    deinit {
        pipController?.delegate = nil
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
    }
}
