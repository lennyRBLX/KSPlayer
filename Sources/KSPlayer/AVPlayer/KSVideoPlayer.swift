//
//  KSVideoPlayer.swift
//  KSPlayer
//
//  Created by kintan on 2023/2/11.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit

public typealias UIViewRepresentable = NSViewRepresentable
#endif

public struct KSVideoPlayer {
    // L7 lane 18: public setter. The trie exports coordinator getter, setter and modify, and a
    // private setter would be stripped under -O WMO. ⚑[tool=export_trie_oracle ref=KSVideoPlayer.coordinator result=vg+vs+vM+vpMV]
    @ObservedObject public var coordinator: Coordinator
    public let url: URL
    public let options: KSOptions
    public init(coordinator: Coordinator, url: URL, options: KSOptions) {
        self.coordinator = coordinator
        self.url = url
        self.options = options
    }
    // L7: Forward 0x1019d6d98 calls the Coordinator init body 0x1019dd320 and reads the MainActor
    // KSPlayerLayer's url/options synchronously with no swift_task_switch or executor check, so the
    // init itself is MainActor-isolated. Order: Coordinator 0x1019dd320, url copy, options load+retain,
    // then ObservedObject(wrappedValue:) store and options store = arguments evaluated, then the
    // memberwise init(coordinator:url:options:) body inlined.
    @MainActor
    public init(playerLayer: KSPlayerLayer) {
        self.init(coordinator: Coordinator(playerLayer: playerLayer), url: playerLayer.url, options: playerLayer.options)
    }

    // L7: Forward 0x1019d6f0c: nil check on Coordinator.playerLayer (cbz → return nil), else the
    // init(playerLayer:) body inlined (0x1019dd320, url, options, ObservedObject), no hop.
    @MainActor
    public init?(coordinator: KSVideoPlayer.Coordinator) {
        guard let playerLayer = coordinator.playerLayer else {
            return nil
        }
        self.init(playerLayer: playerLayer)
    }
}

extension KSVideoPlayer: Equatable {
    public static func == (lhs: KSVideoPlayer, rhs: KSVideoPlayer) -> Bool {
        lhs.url == rhs.url
    }
}

@MainActor
public extension KSVideoPlayer {
    func onBufferChanged(_ handler: @escaping (Int, TimeInterval) -> Void) -> Self {
        coordinator.onBufferChanged = handler
        return self
    }

    /// Playing to the end.
    func onFinish(_ handler: @escaping (KSPlayerLayer, Error?) -> Void) -> Self {
        coordinator.onFinish = handler
        return self
    }

    func onPlay(_ handler: @escaping (TimeInterval, TimeInterval) -> Void) -> Self {
        coordinator.onPlay = handler
        return self
    }

    /// Playback status changes, such as from play to pause.
    func onStateChanged(_ handler: @escaping (KSPlayerLayer, KSPlayerState) -> Void) -> Self {
        coordinator.onStateChanged = handler
        return self
    }
}

extension KSVideoPlayer: UIViewRepresentable {

    #if canImport(UIKit)
    public typealias UIViewType = UIView
    public func makeUIView(context: Context) -> UIViewType {
        context.coordinator.makeView(url: url, options: options)
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        updateView(view, context: context)
    }

    // iOS tvOS真机先调用onDisappear在调用dismantleUIView，但是模拟器就反过来了。
    public static func dismantleUIView(_: UIViewType, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
    #else
    public typealias NSViewType = UIView
    public func makeNSView(context: Context) -> NSViewType {
        context.coordinator.makeView(url: url, options: options)
    }

    public func updateNSView(_ view: NSViewType, context: Context) {
        updateView(view, context: context)
    }

    // macOS先调用onDisappear在调用dismantleNSView
    public static func dismantleNSView(_ view: NSViewType, coordinator: Coordinator) {
        coordinator.resetPlayer()
        view.window?.aspectRatio = CGSize(width: 16, height: 9)
    }
    #endif

    // L7: Forward 0x1019d74a0 (updateUIView 0x1019d749c is a 1-insn merged thunk to it) keeps the
    // view live: first `coordinator.playerLayer?` (ObservedObject storage self+8) vtable +0x288 =
    // KSPlayerLayer.updateUIView(_:) with x0 = the view, then the context.coordinator URL check.
    @MainActor
    private func updateView(_ view: UIView, context: Context) {
        coordinator.playerLayer?.updateUIView(view)
        if context.coordinator.playerLayer?.url != url {
            _ = context.coordinator.makeView(url: url, options: options)
        }
    }

    @MainActor
    public final class Coordinator: ObservableObject {
        // ⚑ STORED, NOT COMPUTED — a type-SHAPE change read from the field records. `_state` is
        //   field record 0 of 15 and its typeref is `Published<KSPlayerState>`, so the binary keeps
        //   a stored `@Published`; a computed property emits no field record and no Published
        //   machinery at all. The default is proven, not assumed: `_state`'s `vpfi` @0x10002dab0 is
        //   `mov w0,#0`, and `.initialized` is case 0.
        //   It has TWO writers, which is what makes a stored property viable — `init(playerLayer:)`
        //   below, and `player(layer:state:)`, which writes it as its FIRST statement.
        // ⚑[tool=fieldrec ref=Coordinator._state:0x1039ed33c result=rec0-Published-KSPlayerState]
        @Published
        public var state: KSPlayerState = .initialized

        @Published
        public var isMuted: Bool = false {
            didSet {
                playerLayer?.player.isMuted = isMuted
            }
        }

        @Published
        public var playbackVolume: Float = 1.0 {
            didSet {
                playerLayer?.player.playbackVolume = playbackVolume
            }
        }

        @Published
        public var isScaleAspectFill = false {
            didSet {
                playerLayer?.player.contentMode = isScaleAspectFill ? .scaleAspectFill : .scaleAspectFit
            }
        }

        // ⚑ BINARY HAS THIS, SOURCE DID NOT — field record 4, `Published<Bool>`, with a complete
        //   public accessor set plus the `$isRecord` projected value. Default false is proven: its
        //   `vpfi` @0x10002dab0 is `mov w0,#0`, ICF-folded with `_isMuted`/`_isScaleAspectFill`/`_state`.
        // L7: didSet body Forward 0x1019d8d28 (called by the setter 0x1019d9488 and modify with the
        // old value): `==` old → exit; false arm → player witness +0x70 stopRecord(); true arm →
        // swift_once KSOptions.recordDir, optional check, playerLayer check, fileExists/createDirectory
        // (willThrow + errorRelease = try?), fileExists again, pathExtension "m3u8"/isEmpty → "ts",
        // Date().description + "." + ext, appendingPathComponent, witness +0x68 startRecord(url:).
        @Published
        public var isRecord: Bool = false {
            didSet {
                if isRecord != oldValue {
                    if isRecord {
                        if let url = KSOptions.recordDir, let playerLayer {
                            if !FileManager.default.fileExists(atPath: url.path) {
                                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            }
                            if FileManager.default.fileExists(atPath: url.path) {
                                var fileExtension = playerLayer.url.pathExtension
                                if fileExtension == "m3u8" || fileExtension.isEmpty {
                                    fileExtension = "ts"
                                }
                                playerLayer.player.startRecord(url: url.appendingPathComponent(Date().description + "." + fileExtension))
                            }
                        }
                    } else {
                        playerLayer?.player.stopRecord()
                    }
                }
            }
        }

        @Published
        public var playbackRate: Float = 1.0 {
            didSet {
                playerLayer?.player.playbackRate = playbackRate
            }
        }

        @Published
        @MainActor
        public var isMaskShow = true {
            didSet {
                if isMaskShow != oldValue {
                    mask(show: isMaskShow)
                }
            }
        }

        // ⚑ REMOVED `subtitleModel` — absent from all 15 Coordinator field records and all 146
        //   Coordinator trie symbols; it lives on KSPlayerLayer (offset global 0x104c63500). Neither
        //   Forward makeView @0x1019d7254 nor resetPlayer @0x1019d7988 loads 0x104c63500, so the two
        //   Coordinator-side uses went with it. SwiftUI readers re-rooted onto `playerLayer?`.
        public var timemodel = ControllerTimeModel()
        // 在SplitView模式下，第二次进入会先调用makeUIView。然后在调用之前的dismantleUIView.所以如果进入的是同一个View的话，就会导致playerLayer被清空了。最准确的方式是在onDisappear清空playerLayer
        public var playerLayer: KSPlayerLayer? {
            didSet {
                oldValue?.delegate = nil
                oldValue?.pause()
            }
        }

        // Stated outright by the export trie, so the payload is read and not inferred:
        // ⚑[tool=export_trie_oracle ref=$s8KSPlayer13KSVideoPlayerV11CoordinatorC9delayHide33_9CE0D5E10C22B47FEFCEFADFDAB1EB55LLScTyyts5Error_pGSgvpfi result=Swift.Task<(),Swift.Error>?]
        // `ScT` is Swift.Task and the trailing `Sg` is present, so the optional was already right;
        // only the payload was wrong. See mask(show:autoHide:) for the write site.
        private var delayHide: Task<Void, Error>?
        public var onPlay: ((TimeInterval, TimeInterval) -> Void)?
        public var onFinish: ((KSPlayerLayer, Error?) -> Void)?
        public var onStateChanged: ((KSPlayerLayer, KSPlayerState) -> Void)?
        public var onBufferChanged: ((Int, TimeInterval) -> Void)?
        public var onURLChanged: ((KSPlayerLayer, URL) -> Void)?

        /// ⚑ RECOVERED — the binary declares this and source did not. Trie-named at BOTH entries:
        /// allocating `0x1019d6ec8`, initializing `0x1019da958`; the shared body they call,
        /// `0x1019dd320` (988 B / 247 instr), is itself NOT_IN_TRIE — unnamed, not unread.
        /// The body performs exactly 15 stores, one per field record, with no literals and no error
        /// path: the seven `@Published` backing stores take their declared defaults, `timemodel`
        /// gets a fresh `ControllerTimeModel()`, `delayHide` and the five closures are nil, then
        /// `playerLayer` is stored, the layer's delegate is set to self (a WEAK store, witness
        /// 0x1041d4d18), and `state` is seeded from the layer.
        /// ⚑[tool=export_trie_oracle ref=Coordinator.init(playerLayer:):0x1019da958 result=OWNER_MATCH]
        public init(playerLayer: KSPlayerLayer) {
            self.playerLayer = playerLayer
            playerLayer.delegate = self
            state = playerLayer.state
        }

        public init() {}

        // L7: Forward 0x1019d7254. Existing layer: delegate = self (weak assign, witness 0x1041d4d18) first,
        // then `!=` (inlined Equatable.!= → dispatch thunk $sSQ2eeoiySbx_xtFZTj), set(url:options:) 0x1019cb674
        // only when different. New layer: static KSOptions.playerLayerType (once 0x1044e51f0) metatype
        // slot +0x270 init(url:options:delegate:), then the playerLayer setter 0x1019da600. Both arms
        // return through KSPlayerLayer vtable +0x280 = makeUIView().
        public func makeView(url: URL, options: KSOptions) -> UIView {
            if let playerLayer {
                playerLayer.delegate = self
                if playerLayer.url != url {
                    playerLayer.set(url: url, options: options)
                }
                return playerLayer.makeUIView()
            } else {
                let playerLayer = KSOptions.playerLayerType.init(url: url, options: options, delegate: self)
                self.playerLayer = playerLayer
                return playerLayer.makeUIView()
            }
        }

        public func resetPlayer() {
            onStateChanged = nil
            onPlay = nil
            onFinish = nil
            onBufferChanged = nil
            delayHide?.cancel()
            delayHide = nil
            // L7: Forward 0x1019d7988 stores playerLayer = nil last (setter 0x1019da600 after the delayHide clear).
            playerLayer = nil
        }

        public func skip(interval: Int) {
            if let playerLayer {
                seek(time: playerLayer.player.currentPlaybackTime + TimeInterval(interval))
            }
        }

        public func seek(time: TimeInterval) {
            playerLayer?.seek(time: TimeInterval(time))
        }

        @MainActor
        public func mask(show: Bool, autoHide: Bool = true) {
            isMaskShow = show
            if show {
                delayHide?.cancel()
                // 播放的时候才自动隐藏
                guard state == .bufferFinished else { return }
                if autoHide {
                    // Forward schedules the auto-hide as a Task, not a DispatchWorkItem +
                    // asyncAfter. Read from mask(show:autoHide:) @0x1019d9d74: the field store at
                    // 0x1019da07c writes the result of the task-creation call at 0x1019da074 into
                    // the delayHide field-offset slot, and the cancel at 0x1019d9f4c dispatches
                    // ⚑[tool=stubs->__got->--macho --bind ref=0x103457c78:0x104113968 result=$sScT6cancelyyF]
                    // (Swift.Task.cancel), never DispatchWorkItem.cancel. The closure is
                    // [weak self]: swift_allocObject(24 B) @0x1019d9fe0 then
                    // ⚑[tool=stubs->__got->--macho --bind ref=0x10345d204:0x104113140 result=_swift_weakInit]
                    // at box+0x10. `priority: nil` is the storeEnumTagSinglePayload(buf,1,1) on
                    // ⚑[tool=stubs->__got->--macho --bind ref=0x103457bc4:0x1041138a8 result=$sScPMa]
                    // (Swift.TaskPriority) at 0x1019d9fcc. MainActor isolation is inherited from
                    // this @MainActor method, not annotated: the body hops through MainActor.shared
                    // + swift_task_switch @0x1019daf6c before the sleep.
                    delayHide = Task { [weak self] in
                        // Body @0x1019daf70: swift_beginAccess on
                        // static KSOptions.animateDelayTimeInterval @0x1044f1810 (export trie),
                        // `fmul` by the literal 0x41CDCD6500000000 = 1000000000.0 exactly, then
                        // `fcvtzu x20, d0` — an unsigned Double->UInt64 conversion with the three
                        // standard overflow traps at 0x1019db020/24/28 — passed to
                        // ⚑[tool=stubs->__got->--macho --bind ref=0x103457ca8:0x104113998 result=$sScTss5NeverORszABRs_rlE5sleep11nanosecondsys6UInt64V_tYaKFZ]
                        // (Task.sleep(nanoseconds:)). `try` is what makes the field Task<(), Error>.
                        try await Task.sleep(nanoseconds: UInt64(KSOptions.animateDelayTimeInterval * 1_000_000_000))
                        // Continuation @0x1019db084, in this order: swift_weakLoadStrong on the
                        // box then `cbz` to the exit (the guard); the Published `state` read
                        // through the same two keypath descriptors 0x103567a90/0x103567ab8 the
                        // guard at line 193 uses, compared `cmp w8, #0x4` = case index 4 =
                        // .bufferFinished; then w0=0 into
                        // ⚑[tool=export_trie_oracle ref=Coordinator.isMaskShow.setter:0x1019da0e0 result=OWNER_MATCH]
                        guard let self else { return }
                        if self.state == .bufferFinished {
                            self.isMaskShow = false
                        }
                    }
                }
            }
            #if os(macOS)
            show ? NSCursor.unhide() : NSCursor.setHiddenUntilMouseMoves(true)
            if let window = playerLayer?.player.view.window {
                if !window.styleMask.contains(.fullScreen) {
                    window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = !show
                    //                    window.standardWindowButton(.zoomButton)?.isHidden = !show
                    //                    window.standardWindowButton(.closeButton)?.isHidden = !show
                    //                    window.standardWindowButton(.miniaturizeButton)?.isHidden = !show
                    //                    window.titleVisibility = show ? .visible : .hidden
                }
            }
            #endif
        }
    }
    public func makeCoordinator() -> Coordinator {
        coordinator
    }
}

extension KSVideoPlayer.Coordinator: KSPlayerLayerDelegate {
    // Two PiP callbacks the binary declares on this type and this source did not. Both bodies
    // are 0x10000e52c — a bare `ret`, i.e. empty. That address is the image's canonical empty
    // body and is heavily ICF-folded, so "the method does nothing" is the whole of what it
    // establishes, and the whole of what these two declare.
    // Signatures from the trie: `KSPlayer.KSVideoPlayer.Coordinator.playerDidStartPip() -> ()`
    // and `…playerDidStopPip() -> ()` — no parameters, no return.
    // Placed in this conformance extension because that is where the binary's own siblings sit;
    // whether they are KSPlayerLayerDelegate REQUIREMENTS is not asserted here, because that
    // would need the protocol descriptor, not a member symbol.
    public func playerDidStartPip() {}

    public func playerDidStopPip() {}

    /// @0x1019db4f0. TWO of this body's source arms are REFUTED by the extent, so the arm shape
    /// below is the binary's rather than the previous reconstruction's:
    ///   · raw {1 preparing, 3 buffering, 4 bufferFinished} — NO store at all. Source's
    ///     `.bufferFinished -> isMaskShow = false` has no counterpart; raw 4 exits cleanly.
    ///   · raw {2 readyToPlay} — `playbackRate = layer.player.playbackRate`, then
    ///     `timemodel.fileSize = layer.player.fileSize`. The old `subtitleDataSource` stub was
    ///     wrong: there is no `subtitleDataSource` read anywhere in this body.
    ///   · raw {0 initialized, 5 paused, 6 playedToTheEnd, 7 error} — `if !isMaskShow { isMaskShow = true }`.
    ///
    /// The `_state` store is the FIRST statement, ahead of `onStateChanged?`, through the
    /// `Published._enclosingInstance` SETTER 0x1034532f8 with the `\.state` / `\._state` keypath
    /// pair (storage keypath -> 0x1044e62b0), inside a DISCARDED `Task` whose operation hops to
    /// MainActor (entry 0x1019dd9b0 -> 0x1019db7cc -> 0x1019db860).
    /// ⚑ SPELLING, approved=jweaver: this class is already `@MainActor`, so a bare `Task { }`
    ///   inherits that isolation and emits exactly this hop. `Task { @MainActor in }` is
    ///   observationally identical here and the two are not separable in this image.
    ///
    /// ⚑ The `#if canImport(UIKit)` swipe-gesture block that stood in this method is GONE, and its
    ///   absence is exhaustive rather than inferred: the else-arm is 22 instructions with no ObjC
    ///   selector references, and the selector `swipeGestureAction:` occurs ZERO times in the image
    ///   while four sibling KSPlayer `@objc` selectors each occur once — a real absence, not an
    ///   `@objc` trie-visibility gap. `onSwipe`, `swipeGestureAction(_:)` and the `onSwipe(_:)`
    ///   builder are REMOVED: none has a Forward symbol or field record.
    public func player(layer: KSPlayerLayer, state: KSPlayerState) {
        Task {
            self.state = state
        }
        onStateChanged?(layer, state)
        if state == .readyToPlay {
            playbackRate = layer.player.playbackRate
            timemodel.fileSize = layer.player.fileSize
        } else if state == .preparing || state == .buffering || state == .bufferFinished {
            // binary: these three raw tags exit with no store.
        } else if !isMaskShow {
            isMaskShow = true
        }
    }

    public func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        onPlay?(currentTime, totalTime)
        guard var current = Int(exactly: ceil(currentTime)),
              var total = Int(exactly: ceil(totalTime)),
              let playableTime = Int(exactly: ceil(layer.player.playableTime))
        else {
            return
        }
        if layer.state.isPlaying {
            current = max(0, current)
            total = max(0, total)
            if total < 1 {
                total = current
            } else {
                // Forward 0x1019dbac4: `cmp x10(total),x8(current); csel x11,x10,x8,lt` = stdlib
                // `min(x, y)` → `y < x ? y : x` with y = total.
                current = min(current, total)
            }
            if timemodel.currentTime != current {
                timemodel.currentTime = current
            }
            if timemodel.totalTime != total {
                timemodel.totalTime = total
            }
        }
        let bufferTime = max(0, playableTime)
        if timemodel.bufferTime != bufferTime {
            timemodel.bufferTime = bufferTime
        }
    }

    public func player(layer: KSPlayerLayer, finish error: Error?) {
        onFinish?(layer, error)
    }

    public func player(layer _: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        onBufferChanged?(bufferedCount, consumeTime)
    }

    public func player(layer: KSPlayerLayer, url: URL) {
        onURLChanged?(layer, url)
    }
}

extension View {
    func then(_ body: (inout Self) -> Void) -> Self {
        var result = self
        body(&result)
        return result
    }
}

/// 这是一个频繁变化的model。View要少用这个
public class ControllerTimeModel: ObservableObject {
    // 改成int才不会频繁更新
    @Published
    public var currentTime = 0
    @Published
    public var totalTime = 1
    @Published
    public var bufferTime = 0
    public var fileSize: Int64 = 1
}
