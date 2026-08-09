//
//  MetalPlayView.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import AVFoundation
import Combine
import CoreMedia
#if canImport(MetalKit)
import MetalKit
#endif
public protocol DisplayLayerDelegate: NSObjectProtocol {
    func change(displayLayer: AVSampleBufferDisplayLayer)
}

public protocol VideoOutput: FrameOutput {
    var renderSource: VideoOutputRenderSourceDelegate? { get set }
    // Source-only; removal derived and ready, but it is its own unit (see the field below).
    var displayLayerDelegate: DisplayLayerDelegate? { get set }
    var options: KSOptions { get set }
    var displayLayer: AVSampleBufferDisplayLayer { get }
    var pixelBuffer: PixelBufferProtocol? { get }
    init(options: KSOptions)
    func invalidate()
    func readNextFrame()
}

public final class MetalPlayView: UIView, @preconcurrency VideoOutput {
    public var displayLayer: AVSampleBufferDisplayLayer {
        displayView.displayLayer
    }

    /// Field-record index 0 — it opens the class, ahead of `formatDescription`.
    /// Default READ from its own `vpfi` @0x10002c740, which is `mov w0,#1` / `ret` ⇒ `true`, and
    /// the designated init re-emits the same store at 0x101a5eea4. Not assumed to be the Bool zero
    /// default. `private` per the trie's discriminator on its accessors.
    /// ⚑[tool=vpfi_initializer_oracle ref=MetalPlayView.isPaused:0x10002c740 result=true]
    private var isPaused: Bool = true
    /// s116: `isDovi` REMOVED — it is not a Forward field. The class's field records hold 17
    /// entries and it is not among them, and a stored property always gets one. What the binary
    /// passes for `isDovi:` is READ, not chosen: the `didSet` computes it as the Optional-TAG test
    /// on `dovi`, at 0x101a5e510 —
    ///     101a5e4a4  ldr  x8, [x8, #0x8f0]     ; the offset global holding 0x78 = dovi
    ///     101a5e4a8  add  x24, x21, x8         ; x24 = &self.dovi
    ///     101a5e510  ldrb w8, [x24, #0x9]      ; dovi's extra tag byte at self+0x81
    ///     101a5e514  cmp  w8, #0x1
    ///     101a5e518  cset w21, ne              ; isDovi = (tag != 1)
    /// Tag 1 IS the nil representation, read from `dovi`'s own `vpfi` @0x10011a290
    /// (`mov x0,#0` / `mov w1,#0x100` / `ret` — payload zero, byte 9 = 1), so `cset ne` is exactly
    /// `dovi != nil`. The `fps` didSet at 0x101a5e850 computes the same argument the same way,
    /// which is the second, independent witness.
    /// ⚑[tool=vpfi_initializer_oracle ref=MetalPlayView.dovi:0x10011a290 result=nil-tag-byte-1]
    ///
    /// ⚠️ THREE THINGS THIS `didSet` DOES THAT THE SOURCE DOES NOT — each its own unit, NOT written
    ///   here because none of them is needed to remove `isDovi`:
    ///   1. an early `guard self.formatDescription != nil else { return }` (`cbz x19` @0x101a5e3ac
    ///      jumping to the epilogue), so `updateVideo` is never reached with nil;
    ///   2. when `oldValue?.naturalSize != newValue.naturalSize`, it rebuilds a `'BGRA'` buffer and
    ///      re-enqueues it into `displayView.layer as! AVSampleBufferDisplayLayer`;
    ///   3. it writes `options.dynamicRange` itself — `.dolbyVision` when `dovi != nil`, else
    ///      `formatDescription.dynamicRange` — under a MODIFY exclusivity access. `updateVideo`'s
    ///      own body never assigns it, so that store belongs to this caller.
    ///   ⚑[tool=export_trie_oracle ref=KSOptions.dynamicRange:0x104c63388 result=vpWvd-named]
    ///
    /// ⚠️ The binary's `updateVideo` takes a NON-Optional `__C.CMFormatDescriptionRef`; KSOptions
    ///   .swift:881 declares `formatDescription: CMFormatDescription?`. Separate unit.
    ///
    /// ✅ REMOVED. The third site — the WRITE that blocked this — is now read: the binary stores
    ///   `self.dovi = frame.dovi`, a raw 10-byte POD copy, and never reads `frame.isDovi` at all.
    ///   In `draw`'s body @0x101a611f4:
    ///       ldur x8,  [frame, #0x7b]   ; frame.dovi bytes 0..7
    ///       ldurh w9, [frame, #0x83]   ; frame.dovi bytes 8..9
    ///       ldr  x10, [x10, #0x8f0]    ; MetalPlayView.dovi offset global -> 0x78
    ///       str  x8,  [self+dovi]      ; 10 bytes, exactly self+0x78..0x81
    ///       strh w9,  [self+dovi, #0x8]
    ///   `VideoVTBFrame` carries BOTH `dovi` (record 10, at frame+0x7b, same `__got` type ref as
    ///   this class's) and `isDovi` (record 11, at frame+0x85) — and frame+0x85 is read NOWHERE in
    ///   the whole 603-instruction body. So the source's `isDovi = frame.isDovi` was the wrong
    ///   field on both sides.
    ///   ⚑[tool=field_offset_vector ref=VideoVTBFrame result=dovi-0x7b-isDovi-0x85]
    ///
    ///   An exhaustive `__text` scan for the offset global 0x1044ea8f0 finds exactly FIVE `dovi`
    ///   sites in the entire image, which is the complete inventory: the two tag READS below
    ///   (`formatDescription` didSet @0x101a5e510 and `fps` didSet @0x101a5e850, each
    ///   `ldrb w8,[&dovi,#0x9] / cmp w8,#1 / cset ne` = `dovi != nil`), this WRITE, and two
    ///   `dovi = nil` stores in the initialisers — which independently re-confirm that the nil
    ///   representation is payload-zero with tag byte 1 (`str xzr` / `mov w9,#0x100` / `strh w9,[+8]`).
    ///   ⚑[tool=recover_field_offsets ref=MetalPlayView.dovi:0x1044ea8f0 result=5-sites-2-reads-1-write-2-nil-init]
    private var formatDescription: CMFormatDescription? {
        didSet {
            options.updateVideo(refreshRate: fps, isDovi: dovi != nil, formatDescription: formatDescription)
        }
    }

    private var fps = Float(60) {
        didSet {
            if fps != oldValue {
                if KSOptions.preferredFrame {
                    let preferredFramesPerSecond = ceil(fps)
                    if #available(iOS 15.0, tvOS 15.0, macOS 14.0, *) {
                        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: preferredFramesPerSecond, maximum: 2 * preferredFramesPerSecond, __preferred: preferredFramesPerSecond)
                    } else {
                        displayLink?.preferredFramesPerSecond = Int(preferredFramesPerSecond) << 1
                    }
                }
                options.updateVideo(refreshRate: fps, isDovi: dovi != nil, formatDescription: formatDescription)
            }
        }
    }

    /// ⚑[tool=field_offset_vector ref=MetalPlayView.rotation result=index-3@0x1c]
    /// Placed HERE, not appended: the binary's field-offset vector puts `rotation` at index 3
    /// (offset 0x1c), between `fps` (2) and `pixelBuffer` (4), and stored-property order is part
    /// of the layout rather than a style choice.
    ///
    /// It is a plain STORED property, not computed — its getter @0x101a5e8b4 is a
    /// `swift_beginAccess` on `self + <offset global 0x1044ea8b0>` followed by a bare `ldrh w0`,
    /// with a matching setter and modify coroutine. A computed property would show work here.
    ///
    /// `public` is PROVEN by its `vpMV` (property descriptor @0x10356b4e0), not inferred from the
    /// enclosing class. The default is READ from its own `vpfi` @0x10002dab0 — `mov w0, #0` /
    /// `ret` — so `= 0` is transcribed, not assumed to be the zero default.
    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.rotation:0x10356b4e0 result=vpMV-public]
    public var rotation: UInt16 = 0
    public private(set) var pixelBuffer: PixelBufferProtocol?
    public var options: KSOptions
    // Binary type is the NARROWER `VideoOutputRenderSourceDelegate?`; OutputRenderSourceDelegate
    // refines it with the audio half, which this view never uses.
    public weak var renderSource: VideoOutputRenderSourceDelegate?
    /// ⚑[tool=field_offset_vector ref=MetalPlayView.drawable result=index-7@0x48]
    /// Placed at its field-record index (7, offset 0x48), between `renderSource` (6) and
    /// `metalView` (8) — layout, not style.
    ///
    /// Stored, not computed: the getter @0x101a5ec80 is a `swift_beginAccess` on
    /// `self + <offset global 0x1044ea8d0>` followed by an outlined indirect copy into the sret
    /// (`bl 0x1001263e0`), with a matching setter and modify coroutine. `public` is proven by its
    /// `vpMV`.
    ///
    /// ⚑ It has NO `vpfi`, so there is no declaration default — writing one would be fabrication.
    ///   The value comes from `init(options:)`, and the assignment there is read in full below.
    public var drawable: Drawable
    private let metalView = MetalView()
    /// Field-record index 9, between `metalView` (8) and `isBackground` (10) — the position the
    /// `isBackground` note below already asserted. Type read from the mangle, which is a ctrl-2
    /// symref to `KSPlayer.DOVIDecoderConfigurationRecord` with a trailing `Sg`, so it is a genuine
    /// Optional and not a bare `T`. `var` from the FieldRecord Flags word (0x00000002). `private`
    /// from the per-file discriminator `33_8CE14EEEDB5CC7973511FB5E09E191F8LL` carried by its own
    /// `vpfi` symbol; there is no `vpMV` and no `vpWvd` for it, and no getter/setter/modify is
    /// exported. No declaration default is written: the `vpfi` @0x10011a290 returns nil, but a
    /// `var` of Optional type emits a `vpfi` whether or not `= nil` was in the source, so the
    /// default is NOT decidable and writing one would be fabrication.
    /// ⚑[tool=dump_field_type_mangles ref=MetalPlayView.dovi:record9 result=DOVIDecoderConfigurationRecord_Sg]
    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.dovi:0x10011a290 result=private-vpfi-only]
    private var dovi: DOVIDecoderConfigurationRecord?
    /// Field-record index 10, between `dovi` (9) and `displayView` (11). Default READ from its
    /// `vpfi` @0x10002dab0 (`mov w0,#0` / `ret`), which it shares with `forcedFrameRetryScheduled`
    /// and `rotation`; the init re-emits the store at 0x101a5ef34.
    /// ⚑[tool=vpfi_initializer_oracle ref=MetalPlayView.isBackground:0x10002dab0 result=false]
    private var isBackground: Bool = false
    // AVSampleBufferAudioRenderer AVSampleBufferRenderSynchronizer AVSampleBufferDisplayLayer
    private var displayView = AVSampleBufferDisplayView() {
        didSet {
            displayLayerDelegate?.change(displayLayer: displayView.displayLayer)
        }
    }

    /// 用displayLink会导致锁屏无法draw，
    /// 用DispatchSourceTimer的话，在播放4k视频的时候repeat的时间会变长,
    /// 用MTKView的draw(in:)也是不行，会卡顿
    // Binary type is `DisplayLinkProtocol?`, not `CADisplayLink!`. DisplayLinkProtocol was
    // reconstructed precisely to abstract UIKit's CADisplayLink and the macOS CVDisplayLink shim
    // behind one interface, and CADisplayLink already conforms — this field never migrated.
    private var displayLink: DisplayLinkProtocol?
    /// Field-record index 13, a `let` (flags 0). Type is the record's own
    /// `So24OS_dispatch_source_timer_p`, i.e. `DispatchSourceTimer`. The initializer is READ from
    /// its 90-instruction `vpfi` @0x10199ae4c: a `TimerFlags` built by `SetAlgebra.init(_:)` over
    /// an EMPTY sequence (`__swiftEmptyArrayStorage`), then `makeTimerSource(flags:queue:)` with
    /// `DispatchQueue.main`.
    /// ⚑ Whether the source spells `flags: []` explicitly or relies on the API default is NOT
    ///   decidable — the default argument is inlined into the vpfi either way. The commented-out
    ///   `timer` line above this class's `displayLink` note carries the same spelling.
    /// ⚑[tool=vpfi_initializer_oracle ref=MetalPlayView.backgroundTimer:0x10199ae4c result=makeTimerSource-main-queue]
    private let backgroundTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    /// Field-record index 14, a `let` (flags 0) with NO `vpfi` — so it has no declaration default
    /// and its value comes from the init. `locate_class_init` answers "0 construction sites", which
    /// is not a dead end: the designated `init(options:)` is at 0x101a5eda8 via the trie, and at
    /// 0x101a5f144 it does `ldrb w8,[options, <KSOptions global 0x104c63400>]` /
    /// `strb w8,[self, <global 0x1044ea928>]`. Both globals are named by their `vpWvd`, so the
    /// source field is READ, not matched by name.
    /// ⚑[tool=export_trie_oracle ref=KSOptions.renderUseDispatchSourceTimer:0x104c63400 result=vpWvd-named-Bool]
    private let renderUseDispatchSourceTimer: Bool
    /// Field-record index 15, immediately after `renderUseDispatchSourceTimer` (14). The mangle is
    /// a bare ctrl-1 direct symref to 0x1039efdcc with an EMPTY tail — no `Sg` — so the field is
    /// the non-optional struct, not an Optional. `var` from the Flags word; `private` from the same
    /// per-file discriminator as `dovi`, carried by its `vpfi`; no `vpMV`, no `vpWvd`, no exported
    /// accessor of any kind.
    ///
    /// ⚑ The default is READ, not chosen: the `vpfi` @0x10199afb4 is not folded (OWNER_MATCH, one
    ///   symbol) and returns the four-register value x0=0 / w1=1 / x2=0 / w3=0, which is
    ///   `FlickerDetector`'s three fields all at their declared defaults (`lastSignature: Int?` nil
    ///   occupying value+tag, `changeCount: Int` 0, `notified: Bool` false). What is NOT decidable
    ///   is the SPELLING — `FlickerDetector()` and the fully-written-out memberwise call compile to
    ///   the same vpfi — so the shorter form is written as the minimal claim.
    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.flickerDetector:0x10199afb4 result=OWNER_MATCH-private-vpfi]
    /// ⚑[tool=fieldrec ref=KSPlayer.FlickerDetector:0x1039efdcc result=3-fields-lastSignature-changeCount-notified]
    ///
    /// ⚠️ Forward spells the TYPE with a per-file discriminator —
    ///   `KSPlayer.(FlickerDetector in _8CE14EEEDB5CC7973511FB5E09E191F8)` — i.e. it is file-private
    ///   to this file there, while this tree declares it `public struct` in Metal/Drawable.swift.
    ///   That placement/access divergence is its own unit and does not change what this field is.
    private var flickerDetector = FlickerDetector()
    /// Field-record index 16 — the LAST field, at instance offset 0xc9 with InstanceSize 0xca.
    /// The mangle is the two bytes `Sb` with no trailing `Sg`, so it is `Bool`, not `Bool?` and not
    /// `Bool!`. `var`, `private` by the same per-file discriminator. Default READ from the `vpfi`
    /// @0x10002dab0 (`mov w0,#0` / `ret`), the same shared body `isBackground` above cites.
    /// ⚑[tool=vpfi_initializer_oracle ref=MetalPlayView.forcedFrameRetryScheduled:0x10002dab0 result=false]
    private var forcedFrameRetryScheduled: Bool = false
//    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    // displayLayerDelegate is a source-only construct. The evidence is stronger than the trie
    // scan this comment used to cite: over the whole 76 MB image the byte sequences
    // `displayLayerDelegate` and `DisplayLayerDelegate` occur ZERO times, against 3 for the
    // control `flickerDetector` — so the absence is the image's, not a search artifact. This
    // class's field descriptor lists 17 records ending at `forcedFrameRetryScheduled` and none
    // is this one, and removing it shifts no offset because it is the last stored property
    // (InstanceSize 0xca, last field at 0xc9).
    // ⚑[tool=fieldrec ref=MetalPlayView:0x1039efd08 result=17-fields-no-displayLayerDelegate]
    //
    // ⚠️ THE REMOVAL IS **NOT** "DERIVED AND READY", WHICH IS WHAT THIS COMMENT SAID BEFORE.
    // It was scoped as a 7-site delete: this protocol, this field, the `VideoOutput` requirement,
    // the displayView didSet call, two `videoOutput?.displayLayerDelegate = self` sites in
    // KSMEPlayer, and `extension KSMEPlayer: DisplayLayerDelegate` with its
    // `change(displayLayer:)`. The first five are safe — every name in them is a zero-hit.
    // The last two are NOT, and deleting them would delete behaviour the binary HAS:
    // `change(displayLayer:)`'s body is what builds the PiP controller, and `pipController`
    // occurs 3 times image-wide as a PUBLIC field of KSMEPlayer, with `ContentSource` likewise
    // at 3. So the binary reaches that setup by SOME route; it simply is not this protocol.
    // ⚑[tool=export_trie_oracle ref=KSMEPlayer.pipController result=public-field-present]
    //
    // Scope it as: (a) drop the five source-only sites, and (b) a SEPARATE unit that derives how
    // the binary invokes the PiP setup and re-homes the body there. Doing (a) without (b) leaves
    // an orphan method with no caller, which is its own divergence.
    public weak var displayLayerDelegate: DisplayLayerDelegate?
    public init(options: KSOptions) {
        self.options = options
        // @0x101a5f144: `ldrb w8,[options, <KSOptions global 0x104c63400>]` then
        // `strb w8,[self, <global 0x1044ea928>]`. Both globals are named by their `vpWvd`, so both
        // sides of this assignment are read rather than matched by name.
        renderUseDispatchSourceTimer = options.renderUseDispatchSourceTimer
        // ⚑[tool=export_trie_oracle ref=MetalPlayView.init(options:):0x101a5eda8 result=drawable-store@0x101a5f0ec]
        // Read from the init, via the OFFSET GLOBAL — this class is `metadata_init=1`, so field
        // accesses index by a register loaded from a per-field global and never use a literal
        // offset. The chain at 0x101a5f098..0x101a5f0f0 is: load `self.<global 0x1044ea8a0>`
        // (= metalView), send `layer` (selref 0x10440bf70), cast, then store into
        // `self + <global 0x1044ea8d0>` (= drawable).
        // ⚑ The cast is FORCED, not conditional: the helper is
        //   `swift_dynamicCastObjCClassUnconditional` (__got 0x104112e20) and the class operand is
        //   `OBJC_CLASS_$_CAMetalLayer` (__objc_classrefs 0x104410d20). A conditional `as?` would
        //   use the nullable variant. `CAMetalLayer : Drawable` is witness 0x1041d9e70.
        // ⚑[tool=bind_oracle ref=__got:0x104112e20 result=swift_dynamicCastObjCClassUnconditional]
        // ⚑[tool=bind_oracle ref=__objc_classrefs:0x104410d20 result=CAMetalLayer]
        drawable = metalView.layer as! CAMetalLayer
        super.init(frame: .zero)
        addSubview(displayView)
        addSubview(metalView)
        metalView.isHidden = true
        //        displayLink = CADisplayLink(block: renderFrame)
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        // 一定要用common。不然在视频上面操作view的话，那就会卡顿了。
        displayLink?.add(to: .main, forMode: .common)
        pause()
    }

    public func play() {
        displayLink?.isPaused = false
    }

    public func pause() {
        displayLink?.isPaused = true
    }

    /// @0x101a602dc, 103 instructions.
    ///
    ///   · `_objc_msgSendSuper2` opens the body ⇒ `super.layoutSubviews()`.
    ///   · `subviews` is sent and bridged with `Array._unconditionallyBridgeFromObjectiveC`, then
    ///     walked; per element `bounds` is sent to self and `setFrame:` to the element.
    ///   · the tail reads `rotation` (offset global 0x1044ea8b0, its own `vpWvd`) with `ldrh` —
    ///     16-bit, matching the `UInt16` declared above — under a (0, 0) beginAccess, and
    ///     `cbz w8` branches to a path that loads a PRECOMPUTED constant pair instead of calling
    ///     the C function. `CGAffineTransformMakeRotation` is not inlinable here, so that branch
    ///     cannot be compiler-introduced on a runtime value: the zero test is in the source.
    ///   · the non-zero arm is `ucvtf d0,w8` (UNSIGNED, matching UInt16) then `fmul` by the double
    ///     at 0x10348c800 = 3.141592653589793 and `fdiv` by the immediate 0x4066800000000000 =
    ///     180.0. Both constants read from the image, not recognised by shape.
    /// ⚑[tool=recover_field_offsets ref=MetalPlayView.rotation:0x1044ea8b0 result=UInt16]
    /// ⚑ The `#if canImport(UIKit)` is OURS, not the binary's. Forward-TF is the iOS build, so the
    ///   image can only ever show this arm; `layoutSubviews` and `transform` are UIView members
    ///   with no NSView counterpart, and this file aliases `UIView` to `NSView` on macOS. The
    ///   guard is what lets the read body coexist with the macOS target, not a claim about a
    ///   second implementation.
    #if canImport(UIKit)
    override public func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            subview.frame = bounds
        }
        transform = rotation == 0 ? .identity : CGAffineTransformMakeRotation(Double(rotation) * .pi / 180)
    }
    #endif

    /// @0x101a6095c, 93 instructions.
    ///
    /// Every field is named from its offset global by `recover_field_offsets --global`, never by
    /// position — this class is `metadata_init=1` and the globals are NOT in field-record order.
    ///   · 0x1044ea8f8 `isBackground`, `strb` of `#1` ⇒ `true`, unconditional and first.
    ///   · 0x1044ea928 `renderUseDispatchSourceTimer` and 0x1044ea8d8 `isPaused`, each `ldrb` then
    ///     `tbnz w8,#0` to the SAME exit — two independent early returns, not one `||` on a pair
    ///     the compiler fused, because each has its own load and its own branch.
    ///   · 0x1044ea908 `backgroundTimer`; 0x1044ea8e8 `fps`, loaded with `ldr s0` (32-bit ⇒ its
    ///     `Float`) then `fcvt d0,s0` and `fdiv d8, 1.0, d0` ⇒ `1 / Double(fps)`.
    ///   · the `leeway` temporary is zeroed (`str xzr`) and then given a tag through the enum
    ///     VWT's `destructiveInjectEnumTag` (offset 0x68) read from __got
    ///     `_$s8Dispatch0A12TimeIntervalO11nanosecondsyACSicACmFWC` — so payload 0, case
    ///     `.nanoseconds` ⇒ `.nanoseconds(0)`.
    ///   · both stack temporaries are sized from their VWTs via `__chkstk_darwin` and destroyed
    ///     after the call; that is ABI, not source.
    /// ⚑[tool=recover_field_offsets ref=MetalPlayView:0x1044ea908 result=backgroundTimer]
    /// ⚑[tool=bind_oracle ref=0x104113310 result=DispatchTimeInterval.nanoseconds-case-tag]
    public func enterBackground() {
        isBackground = true
        if renderUseDispatchSourceTimer {
            return
        }
        if isPaused {
            return
        }
        backgroundTimer.schedule(deadline: .now(), repeating: 1 / Double(fps), leeway: .nanoseconds(0))
    }

    /// @0x101a60ad0, 156 instructions. NOT `enterBackground`'s mirror: the timer branch is an `if`,
    /// not an early return — `ldrb` of 0x1044ea928 then `tbnz w8,#0` skips ONLY the schedule and
    /// falls through to the rest of the body — and `isPaused` is never read here.
    ///
    /// Every field is named from its offset global by `recover_field_offsets --global`, never by
    /// position, because this class is `metadata_init=1`:
    ///   · 0x1044ea8f8 `isBackground`, `strb wzr` ⇒ `false`, unconditional and first;
    ///   · 0x1044ea928 `renderUseDispatchSourceTimer`; 0x1044ea908 `backgroundTimer`;
    ///   · 0x1044ea8a0 `metalView`, receiver of `objc_msgSend[isHidden]` whose `cbz w0` returns —
    ///     so the guard passes when it IS hidden;
    ///   · 0x1044ea8b8 `pixelBuffer`, read under `swift_beginAccess` as TWO words, which is the
    ///     existential `PixelBufferProtocol?` (ref, witness table), not a bare CVPixelBuffer;
    ///   · 0x1044ea8e0 `formatDescription`; 0x1044ea8a8 `displayView`.
    /// ⚑[tool=recover_field_offsets ref=MetalPlayView.isBackground:0x1044ea8f8 result=isBackground]
    /// ⚑[tool=recover_field_offsets ref=MetalPlayView.pixelBuffer:0x1044ea8b8 result=pixelBuffer]
    ///
    /// `.distantFuture` is the `DispatchTime` static getter at 0x103456814; `.never` is the case
    /// tag in __got 0x104113320, injected through the DispatchTimeInterval VWT's
    /// `destructiveInjectEnumTag` at offset 0x68 exactly as `enterBackground` does, and the leeway
    /// temporary is zeroed before its own tag from 0x104113310 ⇒ `.nanoseconds(0)`.
    /// ⚑[tool=bind_oracle ref=MetalPlayView.enterForeground:0x104113320 result=DispatchTimeInterval-never-case-tag]
    ///
    /// The second guard's witness is READ, not inferred from the source's shape: the call is
    /// `blr [wt+0xc8]`, and slot 24 of the CVBuffer conformance table 0x1041d9f98 — decoded at
    /// `wt+8*(slot+1)` and controlled against the slot-21 answer this file already records —
    /// holds 0x101a88ef0, which the trie names `CVBufferRef.cvPixelBuffer.getter`.
    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.enterForeground:0x101a88ef0 result=cvPixelBuffer-getter]
    ///
    /// The tail loads the `displayView` FIELD and inlines `layer as!` against classref 0x104410d18
    /// (`_OBJC_CLASS_$_AVSampleBufferDisplayLayer`) rather than calling any getter; on this `final`
    /// class `displayView.displayLayer` and `self.displayLayer` inline identically, and the field
    /// load is what the binary shows.
    /// ⚑ Access is NOT readable here: a `final` class emits no method descriptor, so `public`
    ///   follows its sibling `enterBackground` rather than being derived. An ACCESS-bucket
    ///   correction, if any, is a separate row.
    ///   ⚑[tool=export_trie_oracle ref=MetalPlayView.enterForeground:0x101a60ad0 result=no-private-discriminator]
    public func enterForeground() {
        isBackground = false
        if !renderUseDispatchSourceTimer {
            backgroundTimer.schedule(deadline: .distantFuture, repeating: .never, leeway: .nanoseconds(0))
        }
        guard metalView.isHidden else {
            return
        }
        guard let pixelBuffer else {
            return
        }
        guard let imageBuffer = pixelBuffer.cvPixelBuffer else {
            return
        }
        if let formatDescription {
            displayView.displayLayer.enqueue(imageBuffer: imageBuffer, formatDescription: formatDescription)
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.leftAnchor.constraint(equalTo: leftAnchor),
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor),
            subview.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    override public var contentMode: UIViewContentMode {
        didSet {
            metalView.contentMode = contentMode
            switch contentMode {
            case .scaleToFill:
                displayView.displayLayer.videoGravity = .resize
            case .scaleAspectFit, .center:
                displayView.displayLayer.videoGravity = .resizeAspect
            case .scaleAspectFill:
                displayView.displayLayer.videoGravity = .resizeAspectFill
            default:
                break
            }
        }
    }

    #if canImport(UIKit)
    override public func touchesMoved(_ touches: Set<UITouch>, with: UIEvent?) {
        if !options.display.isSphere {
            super.touchesMoved(touches, with: with)
        } else {
            options.display.touchesMoved(touch: touches.first!)
        }
    }
    #else
    override public func touchesMoved(with event: NSEvent) {
        if !options.display.isSphere {
            super.touchesMoved(with: event)
        } else {
            options.display.touchesMoved(touch: event.allTouches().first!)
        }
    }
    #endif

    public func flush() {
        pixelBuffer = nil
        if displayView.isHidden {
            metalView.clear()
        } else {
            displayView.displayLayer.flushAndRemoveImage()
        }
    }

    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.didStartPIP(to:):0x101a6305c result=18-instr]
    ///   · `bl 0x103463f40` is an ObjC send whose selref 0x10440bd98 decodes to **`isHidden`**;
    ///     `tbnz w0,#0` skips the call when it is true, hence the negation.
    ///     ⚑[tool=decode_objc_selector ref=0x10440bd98 result='isHidden']
    ///   · `bl 0x1019f245c` is `UIView.addSub(view:)` (UXKit.swift, reconstructed alongside this).
    ///     The registers fix the direction: swiftself is the incoming `to:` view and the argument
    ///     is the field, so the field is added INTO `view`.
    ///
    /// ⚑ The receiver is `metalView`, and the anchor is BINARY-INTERNAL. Its offset global
    ///   0x1044ea8a0 has no `vpWvd`, so the name cannot be read directly. `init(options:)`
    ///   @0x101a5f098 loads this same global, sends `layer` (selref 0x10440bf70) and casts the
    ///   result to `CAMetalLayer` — the conformance witness 0x1041d9e70 is
    ///   `$sSo12CAMetalLayerC8KSPlayer8DrawableACWP`. Only `MetalView` has
    ///   `layerClass = CAMetalLayer.self` (line 321); `AVSampleBufferDisplayView` declares
    ///   `AVSampleBufferDisplayLayer` (line 395). So 0x1044ea8a0 is `metalView`.
    /// ⚑ An EARLIER version of this comment named it `displayView`, cross-referenced from
    ///   `flush()`'s SOURCE. That was wrong: `flush()` is itself mis-reconstructed against the
    ///   binary (its else-branch reads `drawable` @0x8d0, which no `displayLayer` access explains),
    ///   so anchoring on it anchored on an unverified body. Anchor on binary facts — a witness
    ///   table, a `vpWvd`, a decoded selector — never on reconstructed source.
    /// ⚑ Do NOT extrapolate from the neighbouring `vpWvd` globals (0x1044ea8b0 rotation · 8b8
    ///   pixelBuffer · 8c0 options · 8c8 renderSource · 8d0 drawable): they are contiguous at
    ///   stride 8, but extending that run backward gives 0x8a0 → `formatDescription`, which cannot
    ///   answer `isHidden`. The global array is not index-ordered across this class.
    override public func didStartPIP(to view: UIView) {
        if !metalView.isHidden {
            view.addSub(view: metalView)
        }
    }

    /// ⚑[tool=export_trie_oracle ref=MetalPlayView.didStopPIP():0x101a5e2d8 result=20-instr]
    /// Shares `didStartPIP`'s guard exactly — the same `isHidden` send on the same global
    /// 0x1044ea8a0 (`metalView`, see above), with `tbz w0,#0` branching to the work when the
    /// bit is CLEAR, i.e. when it is not hidden.
    ///
    /// The direction of the re-parent is the mirror of `didStartPIP` and is read from the
    /// registers, not assumed: here `bl 0x1019f245c` leaves swiftself as **self** and passes
    /// `metalView` as the argument, so the view comes BACK into this one.
    ///   · `bl 0x10345ece0` → selref 0x10440a900 = **`bounds`**, sent to `self`.
    ///   · the tail `b 0x103469bc0` → selref 0x10440d4b8 = **`setFrame:`**, sent to `displayView`
    ///     with that rect still live in the FP registers — i.e. `metalView.frame = bounds`.
    /// ⚑[tool=decode_objc_selector ref=0x10440a900 result='bounds']
    /// ⚑[tool=decode_objc_selector ref=0x10440d4b8 result='setFrame:']
    override public func didStopPIP() {
        if !metalView.isHidden {
            addSub(view: metalView)
            metalView.frame = bounds
        }
    }

    public func invalidate() {
        displayLink?.invalidate()
    }

    public func readNextFrame() {
        draw(force: true)
    }

//    deinit {
//        print()
//    }
}

extension MetalPlayView {
    @objc private func renderFrame() {
        draw(force: false)
    }

    private func draw(force: Bool) {
        autoreleasepool {
            guard let frame = renderSource?.getVideoOutputRender(force: force) else {
                return
            }
            pixelBuffer = frame.pixelBuffer
            guard let pixelBuffer else {
                return
            }
            // The binary copies the frame's `dovi` RECORD, not its `isDovi` Bool: a 10-byte POD
            // move `ldur x8,[frame,#0x7b]` / `ldurh w9,[frame,#0x83]` into self+0x78..0x81.
            // frame+0x85 (`VideoVTBFrame.isDovi`) is read nowhere in the 603-instruction body.
            dovi = frame.dovi
            fps = frame.fps
            let cmtime = frame.cmtime
            let par = pixelBuffer.size
            let sar = pixelBuffer.aspectRatio
            // The two arguments come from the binary's own signature. `isHDRScreen` is the static
            // KSOptions.isHDRScreen, which is Optional there; the `?? false` coalesce at this call
            // site is OURS — the default is not read from the caller.
            if let pixelBuffer = pixelBuffer.cvPixelBuffer,
               options.isUseDisplayLayer(frame: frame, isHDRScreen: KSOptions.isHDRScreen ?? false) {
                if displayView.isHidden {
                    displayView.isHidden = false
                    metalView.isHidden = true
                    metalView.clear()
                }
                if let dar = options.customizeDar(sar: sar, par: par) {
                    pixelBuffer.aspectRatio = CGSize(width: dar.width, height: dar.height * par.width / par.height)
                }
                checkFormatDescription(pixelBuffer: pixelBuffer)
                set(pixelBuffer: pixelBuffer, time: cmtime)
            } else {
                if !displayView.isHidden {
                    displayView.isHidden = true
                    metalView.isHidden = false
                    displayView.displayLayer.flushAndRemoveImage()
                }
                let size: CGSize
                if !options.display.isSphere {
                    if let dar = options.customizeDar(sar: sar, par: par) {
                        size = CGSize(width: par.width, height: par.width * dar.height / dar.width)
                    } else {
                        size = CGSize(width: par.width, height: par.height * sar.height / sar.width)
                    }
                } else {
                    size = KSOptions.sceneSize
                }
                checkFormatDescription(pixelBuffer: pixelBuffer)
                #if !os(tvOS)
                if #available(iOS 16, *) {
                    metalView.metalLayer.edrMetadata = frame.edrMetadata
                }
                #endif
                metalView.draw(frame: frame, display: options.display, size: size)
            }
            renderSource?.setVideo(time: cmtime, position: frame.position)
        }
    }

    private func checkFormatDescription(pixelBuffer: PixelBufferProtocol) {
        if formatDescription == nil || !pixelBuffer.matche(formatDescription: formatDescription!) {
            if formatDescription != nil {
                displayView.removeFromSuperview()
                displayView = AVSampleBufferDisplayView()
                displayView.frame = frame
                addSubview(displayView)
            }
            formatDescription = pixelBuffer.formatDescription
        }
    }

    private func set(pixelBuffer: CVPixelBuffer, time: CMTime) {
        guard let formatDescription else { return }
        displayView.enqueue(imageBuffer: pixelBuffer, formatDescription: formatDescription, time: time)
    }
}

class MetalView: UIView {
    // NO STORED PROPERTIES. MetalView's binary field descriptor reports NumFields=0, so the
    // `private let render = MetalRender()` that used to sit here is a field the binary does not
    // have. It is not needed either: the render entry point is an extension on
    // MTLRenderCommandEncoder and everything else MetalRender exposes is static.
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { CAMetalLayer.self }
    #endif
    public var metalLayer: CAMetalLayer {
        // swiftlint:disable force_cast
        layer as! CAMetalLayer
        // swiftlint:enable force_cast
    }

    init() {
        super.init(frame: .zero)
        #if !canImport(UIKit)
        layer = CAMetalLayer()
        #endif
        metalLayer.device = MetalRender.device
        metalLayer.framebufferOnly = true
//        metalLayer.displaySyncEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        if let drawable = metalLayer.nextDrawable() {
            MetalRender.clear(drawable: drawable)
        }
    }

    // Carries the FRAME rather than the pixel buffer, because DisplayEnum's requirement is
    // set(frame:encoder:). Every caller already had a frame in scope.
    func draw(frame: VideoVTBFrame, display: any DisplayEnum, size: CGSize) {
        // No unwrap: VideoVTBFrame.pixelBuffer is a non-optional `let` in the source now too, so
        // this matches the binary, which loads the field with no nil check.
        let pixelBuffer = frame.pixelBuffer
        metalLayer.drawableSize = size
        metalLayer.pixelFormat = KSOptions.colorPixelFormat(bitDepth: pixelBuffer.bitDepth)
        let colorspace = pixelBuffer.colorspace
        if colorspace != nil, metalLayer.colorspace != colorspace {
            metalLayer.colorspace = colorspace
            KSLog("[video] CAMetalLayer colorspace \(String(describing: colorspace))")
            #if !os(tvOS)
            if #available(iOS 16.0, *) {
                if let name = colorspace?.name, name != CGColorSpace.sRGB {
                    #if os(macOS)
                    metalLayer.wantsExtendedDynamicRangeContent = window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0 > 1.0
                    #else
                    metalLayer.wantsExtendedDynamicRangeContent = true
                    #endif
                } else {
                    metalLayer.wantsExtendedDynamicRangeContent = false
                }
                KSLog("[video] CAMetalLayer wantsExtendedDynamicRangeContent \(metalLayer.wantsExtendedDynamicRangeContent)")
            }
            #endif
        }
        guard let drawable = metalLayer.nextDrawable() else {
            KSLog("[video] CAMetalLayer not readyForMoreMediaData")
            return
        }
        MetalRender.renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard let commandBuffer = MetalRender.commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: MetalRender.renderPassDescriptor)
        else {
            return
        }
        encoder.draw(frame: frame, display: display)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

class AVSampleBufferDisplayView: UIView {
    #if canImport(UIKit)
    override public class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    #endif
    var displayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable force_cast
        layer as! AVSampleBufferDisplayLayer
        // swiftlint:enable force_cast
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if !canImport(UIKit)
        layer = AVSampleBufferDisplayLayer()
        #endif
        var controlTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &controlTimebase)
        if let controlTimebase {
            displayLayer.controlTimebase = controlTimebase
            CMTimebaseSetTime(controlTimebase, time: .zero)
            CMTimebaseSetRate(controlTimebase, rate: 1.0)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func enqueue(imageBuffer: CVPixelBuffer, formatDescription: CMVideoFormatDescription, time: CMTime) {
        let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        //        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescription: formatDescription, sampleTiming: [timing], sampleBufferOut: &sampleBuffer)
        if let sampleBuffer {
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [NSMutableDictionary], let dic = attachmentsArray.first {
                dic[kCMSampleAttachmentKey_DisplayImmediately] = true
            }
            if displayLayer.isReadyForMoreMediaData {
                displayLayer.enqueue(sampleBuffer)
            } else {
                KSLog("[video] AVSampleBufferDisplayLayer not readyForMoreMediaData. video time \(time), controlTime \(displayLayer.timebase.time) ")
                displayLayer.enqueue(sampleBuffer)
            }
            if #available(macOS 11.0, iOS 14, tvOS 14, *) {
                if displayLayer.requiresFlushToResumeDecoding {
                    KSLog("[video] AVSampleBufferDisplayLayer requiresFlushToResumeDecoding so flush")
                    displayLayer.flush()
                }
            }
            if displayLayer.status == .failed {
                KSLog("[video] AVSampleBufferDisplayLayer status failed so flush")
                displayLayer.flush()
                //                    if let error = displayLayer.error as NSError?, error.code == -11847 {
                //                        displayLayer.stopRequestingMediaData()
                //                    }
            }
        }
    }
}

/// `enqueue(imageBuffer:formatDescription:)` @0x101a61f60, 439 instructions, four call sites
/// image-wide (0x101a5e46c, 0x101a5f410, 0x101a60d10 = `MetalPlayView.enterForeground`,
/// 0x101a614c0). Forward carries this member on the LAYER, not on `AVSampleBufferDisplayView`, and
/// with two labels rather than three: the receiver arrives in swiftself as the result of
/// `swift_dynamicCastObjCClassUnconditional` against classref 0x104410d18, which binds
/// `_OBJC_CLASS_$_AVSampleBufferDisplayLayer`. The `time:` argument is gone and nothing replaces
/// it — the timing struct is built only from `kCMTimeInvalid` (__got 0x1041091c0) and `kCMTimeZero`
/// (__got 0x1041091d8), and the not-ready message no longer interpolates it.
///
/// NOT_IN_TRIE here is expected and is NOT evidence of absence: no private KSPlayer method is
/// exported at all — `checkFormatDescription` and `MetalPlayView.set` return zero trie hits by the
/// same probe, while private STORED properties (`displayView`'s `vpfi`) do appear. The NAME is
/// READ, not invented: the three KSLog sites pass their `#function` default argument as a
/// 39-character literal at 0x103d36ca0, in argument position on the LogHandler witness, beside its
/// 28-character `#file` companion at 0x103d36c80 and the line number in `w6`. That is precisely the
/// discriminator the s111 KVC-key refutation demands — a logging ARGUMENT, not a string handed to a
/// witness dispatch or a dynamic cast. (`name_exhaustion_gate` returns ROUTE-OPEN on this address,
/// so rule 1 governs and an invented name would not have been permitted anyway.)
/// ⚑[tool=decode_string_literal ref=AVSampleBufferDisplayLayer.enqueue:0x103d36ca0 result=enqueue-imageBuffer-formatDescription]
/// ⚑[tool=bind_oracle ref=AVSampleBufferDisplayLayer.enqueue:0x104410d18 result=AVSampleBufferDisplayLayer]
///
/// The OSStatus is CHECKED, unlike upstream: `cbnz w0` and the optional's `cbz x8` both exit to the
/// same epilogue, which is one `if … == noErr, let sampleBuffer`. `sampleTiming: [timing]` is read,
/// not assumed — the pointer handed to CoreMedia is `x15 + 0x20`, the element offset of a
/// stack-promoted Swift array literal, with the 72-byte timing struct written at that offset.
///
/// The iOS-17 split is read: `bl 0x10345b764` is `__isPlatformVersionAtLeast(2, 17, 0, 0)` and
/// platform 2 is iOS. Its result is held in `w24` across the whole body and selects a receiver
/// twice. `flush`, `isReadyForMoreMediaData` and `enqueueSampleBuffer:` all go to the SELECTED
/// receiver, which is released with `swift_unknownObjectRelease` — a class-constrained existential,
/// not a concrete class. `requiresFlushToResumeDecoding` and `status` are re-fetched inside their
/// own branch instead, which is exactly the split `AVQueuedSampleBufferRendering` forces: neither is
/// a member of that protocol.
/// ⚑[tool=body_fingerprint ref=AVSampleBufferDisplayLayer.enqueue:0x101a61f60 result=ios17-availability-split]
/// ⚑ The `#available` list carries iOS only. The image encodes ONE platform check; the minimum
///   versions for the other three platforms are not recoverable from it.
///   ⚑[tool=llvm-objdump ref=AVSampleBufferDisplayLayer.enqueue:0x101a6212c result=platform2-major17]
///
/// Log levels are case INDICES, not rawValues. The two `w0=#3` sites are `.warning`, which is
/// `KSLog`'s default and therefore unspelled; the `w0=#2` site is `.error` and is spelled. Each
/// site's gate is `cmp w8,#3` / `cmp w8,#2` against the `KSOptions.logLevel` tag, the folded form of
/// `level.rawValue <= KSOptions.logLevel.rawValue` already recorded at KSOptions.swift:1582.
/// ⚑[tool=decode_string_literal ref=AVSampleBufferDisplayLayer.enqueue:0x103d36cd0 result=status-failed-so-flush]
extension AVSampleBufferDisplayLayer {
    func enqueue(imageBuffer: CVPixelBuffer, formatDescription: CMVideoFormatDescription) {
        let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        if CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescription: formatDescription, sampleTiming: [timing], sampleBufferOut: &sampleBuffer) == noErr, let sampleBuffer {
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as? [NSMutableDictionary], let dic = attachmentsArray.first {
                dic[kCMSampleAttachmentKey_DisplayImmediately] = true
            }
            let renderer: AVQueuedSampleBufferRendering
            let requiresFlushToResumeDecoding: Bool
            if #available(iOS 17.0, *) {
                renderer = sampleBufferRenderer
                requiresFlushToResumeDecoding = sampleBufferRenderer.requiresFlushToResumeDecoding
            } else {
                renderer = self
                requiresFlushToResumeDecoding = self.requiresFlushToResumeDecoding
            }
            if requiresFlushToResumeDecoding {
                KSLog("[video] AVSampleBufferDisplayLayer requiresFlushToResumeDecoding so flush")
                renderer.flush()
            }
            if renderer.isReadyForMoreMediaData {
                renderer.enqueue(sampleBuffer)
            } else {
                KSLog("[video] AVSampleBufferDisplayLayer not readyForMoreMediaData. controlTime \(timebase.time) ")
                renderer.enqueue(sampleBuffer)
            }
            let status: AVQueuedSampleBufferRenderingStatus
            if #available(iOS 17.0, *) {
                status = sampleBufferRenderer.status
            } else {
                status = self.status
            }
            if status == .failed {
                KSLog(level: .error, "[video] AVSampleBufferDisplayLayer status failed so flush")
                renderer.flush()
            }
        }
    }
}

#if os(macOS)
import CoreVideo

class CADisplayLink {
    private let displayLink: CVDisplayLink
    private var runloop: RunLoop?
    private var mode = RunLoop.Mode.default
    public var preferredFramesPerSecond = 60
    @available(macOS 12.0, *)
    public var preferredFrameRateRange: CAFrameRateRange {
        get {
            CAFrameRateRange()
        }
        set {}
    }

    public var timestamp: TimeInterval {
        var timeStamp = CVTimeStamp()
        if CVDisplayLinkGetCurrentTime(displayLink, &timeStamp) == kCVReturnSuccess, (timeStamp.flags & CVTimeStampFlags.hostTimeValid.rawValue) != 0 {
            return TimeInterval(timeStamp.hostTime / NSEC_PER_SEC)
        }
        return 0
    }

    public var duration: TimeInterval {
        CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLink)
    }

    public var targetTimestamp: TimeInterval {
        duration + timestamp
    }

    public var isPaused: Bool {
        get {
            !CVDisplayLinkIsRunning(displayLink)
        }
        set {
            if newValue {
                CVDisplayLinkStop(displayLink)
            } else {
                CVDisplayLinkStart(displayLink)
            }
        }
    }

    public init(target: NSObject, selector: Selector) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { [weak self] _, _, _, _, _ in
            guard let self else { return kCVReturnSuccess }
            self.runloop?.perform(selector, target: target, argument: self, order: 0, modes: [self.mode])
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    public init(block: @escaping (() -> Void)) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { _, _, _, _, _ in
            block()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    open func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        self.runloop = runloop
        self.mode = mode
    }

    public func invalidate() {
        isPaused = true
        runloop = nil
        CVDisplayLinkSetOutputHandler(displayLink) { _, _, _, _, _ in
            kCVReturnError
        }
    }
}
#endif
