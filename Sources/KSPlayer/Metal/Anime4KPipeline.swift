//
//  Anime4KPipeline.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `Anime4KPipeline` owns the Anime4K upscaler's per-frame state:
//  the `Anime4K` shader objects, the frame-in-flight bookkeeping, the compiled/target resolutions
//  and the downgrade policy. Root class (super=None), conforms to `KSPlayer.VideoPipeline`.
//
//  FILE NAME IS NOT A CHOICE. Two bodies materialize a `#fileID` of "KSPlayer/Anime4KPipeline.swift"
//  — configure(pixelBuffer:) @0x101a78f84 and encode(commandBuffer:outputTexture:) @0x101a7a5c4 —
//  so the basename is fixed by the binary. `#fileID` carries module/basename only, so the directory
//  is free; it sits beside Anime4K.swift because that is the class it holds.
//
//  ⚑ THIS COMMIT IS A PARTIAL (commit 1 of the Anime4KPipeline stand-up):
//    • The 25-field LAYOUT is FULLY decoded and cross-checked TWICE, which is why it is committed
//      whole: names/order/let-var from the __swift5_fieldmd records (descriptor 0x1039f0a54), byte
//      offsets from the field-offset vector @0x1044ebe58 (InstanceSize 0xe0, static — this class's
//      metadata is NOT runtime-initialized), and every declaration default read from its own
//      variable-initialization-expression body. The compiler's field-init prologue @0x101a7c51c
//      then re-establishes all 22 defaults a SECOND, independent way, store by store, and agrees.
//    • FIVE bodies are reconstructed in full because they were read end to end: init, and the four
//      small methods below. Their instruction counts are 19 / 6 / 6 / 2 / 20.
//    • `loadPreset(_:)` is DECLARED but its body is PINNED — init's tail call to it at 0x101a7c5c0
//      is decoded, the 156-instruction body it lands in is not.
//    • The five REMAINING methods the trie exports (beginFrameRendering, configure,
//      isUpscaleSupported, encode, getPerformanceStats) are deliberately NOT declared here. Each
//      needs its own unit; declaring a signature whose body would have to invent a return value is
//      the one thing the reconstruction may not do.
//    • access level `public` from the exported __allocating_init + type metadata; the fields
//      carrying the `_DF46D33768ECCE03732A95D92124F098` private discriminator are written `private`,
//      and `inputTexture` is not (it alone has a property descriptor @0x1041d9968 and a method
//      descriptor for its getter, i.e. it is the class's one exposed stored property).
//
import Foundation
import Metal
import QuartzCore

public class Anime4KPipeline: VideoPipeline {
    // Field order, let/var and byte offsets are the binary's, not a preference.
    // offsets: device 0x10 · anime4Ks 0x18 · preset 0x20 · usePrecompiled 0x21 ·
    // maxUpscaleInputHeight 0x28 · cachedUpscaleSupport 0x31 · frameStateLock 0x38 ·
    // inFlightFrameCount 0x40 · reservedFrameCount 0x48 · inputTexture 0x50 · videoWidth 0x58 ·
    // videoHeight 0x60 · compiledVideoWidth 0x68 · compiledVideoHeight 0x70 ·
    // compiledDisplayWidth 0x78 · compiledDisplayHeight 0x80 · configured 0x88 · supported 0x89 ·
    // overrideTargetResolution 0x90 · lastFrameTime 0xa8 · frameTimeHistory 0xb0 ·
    // maxHistoryCount 0xb8 · lastPerformanceWarningTime 0xc0 · isDowngraded 0xc8 ·
    // onDowngradePreset 0xd0
    let device: MTLDevice
    private var anime4Ks: [Anime4K] = []
    private var preset: Anime4KPreset
    // No variable-initialization-expression symbol exists for this field, unlike all 22 that carry
    // a declaration default, so it is assigned in the init body rather than at the declaration.
    let usePrecompiled: Bool
    private var maxUpscaleInputHeight: Int?
    private var cachedUpscaleSupport: Bool?
    private let frameStateLock = NSLock()
    private var inFlightFrameCount: Int = 0
    private var reservedFrameCount: Int = 0
    public var inputTexture: MTLTexture?
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    private var compiledVideoWidth: Int = 0
    private var compiledVideoHeight: Int = 0
    private var compiledDisplayWidth: Int = 0
    private var compiledDisplayHeight: Int = 0
    private var configured: Bool = false
    private var supported: Bool = false
    private var overrideTargetResolution: CGSize?
    private var lastFrameTime: Double = 0
    private var frameTimeHistory: [Double] = []
    // The one non-trivial declaration default in the class: `mov w0, #0x1e` = 30.
    private let maxHistoryCount: Int = 30
    private var lastPerformanceWarningTime: Double = 0
    private var isDowngraded: Bool = false
    private var onDowngradePreset: (() -> Void)?

    // Body @0x101a78a58 (19 instr) plus its field-init prologue @0x101a7c51c (48 instr), both read
    // in full. The prologue installs every declaration default above, then stores device (+0x10),
    // preset (+0x20) and usePrecompiled (+0x21, from the constant 1 still live in w8), retains the
    // device and the closure, and TAIL-CALLS loadPreset at 0x101a7c5c0 with the preset in x0.
    public init(device: MTLDevice, preset: Anime4KPreset, onDowngradePreset: (() -> Void)?) {
        self.device = device
        self.preset = preset
        usePrecompiled = true
        self.onDowngradePreset = onDowngradePreset
        loadPreset(preset)
    }

    // Body @0x101a78aa4, 6 instr, read in full:
    //   stp x0, x1, [x20, #0x90] · strb w2, [x20, #0xa0]   -> overrideTargetResolution = value+tag
    //   strb wzr, [x20, #0x88]                             -> configured = false
    //   mov w8, #0x2 · strb w8, [x20, #0x31]               -> cachedUpscaleSupport = nil (tag 2)
    public func updateTargetResolution(_ resolution: CGSize?) {
        overrideTargetResolution = resolution
        configured = false
        cachedUpscaleSupport = nil
    }

    // Body @0x101a7a34c, 6 instr, read in full — the same invalidation pair as above, against
    // maxUpscaleInputHeight (+0x28 value, +0x30 tag).
    public func updateUpscalePolicy(maxInputHeight: Int?) {
        maxUpscaleInputHeight = maxInputHeight
        configured = false
        cachedUpscaleSupport = nil
    }

    // Body @0x1003b9624, 2 instr, read in full: `ldrb w0, [x20, #0x31]` · `ret`. +0x31 is
    // cachedUpscaleSupport, and its nil tag is 2 — which is exactly what the two methods above
    // store to invalidate it.
    public func cachedUpscaleSupportStatus() -> Bool? {
        cachedUpscaleSupport
    }

    // ⚑ 0x101a78abc is a 1-instruction thunk `b 0x101a7c288`; the body is the 23 instructions
    // there, read in full. `force` is NEVER read — no argument register is touched.
    //   ldr x19,[x20,#0x38] -> frameStateLock ; objc `lock`     (selref 0x10440c080)
    //   ldr x8, [x20,#0x40] -> inFlightFrameCount
    //   if x8 == 0 { store 1 to +0x40 ; adds/b.vs +1 into +0x48 -> reservedFrameCount }
    //   cset w20, eq        -> the RETURN is "inFlightFrameCount WAS zero", computed from the
    //                          value loaded BEFORE the store, which is why it is captured first
    //   objc `unlock` (selref 0x10440e750) ; return w20
    // Offsets resolved to names by field_offset_vector (this class's vector is static and fully
    // decoded), so +0x38/+0x40/+0x48 are read, not matched by position.
    // ⚑[tool=decode_objc_selector ref=lock:0x103464ae0 result=lock]
    // ⚑[tool=decode_objc_selector ref=unlock:0x10346e620 result=unlock]
    public func beginFrameRendering(force _: Bool) -> Bool {
        frameStateLock.lock()
        let wasIdle = inFlightFrameCount == 0
        if wasIdle {
            inFlightFrameCount = 1
            reservedFrameCount += 1
        }
        frameStateLock.unlock()
        return wasIdle
    }

    // Body @0x101a78ac0, 20 instr, read in full. The guard is `subs x8, [x20,#0x48], #1` + `b.lt`,
    // so the block runs only when reservedFrameCount >= 1; the decrement reuses that same
    // subtraction. `bic x8, x8, x8, asr #63` is max(_, 0), and the unlock at 0x101a78b08 is a TAIL
    // CALL reached from both the taken and the skipped path.
    public func cancelFrameRendering() {
        frameStateLock.lock()
        if reservedFrameCount > 0 {
            reservedFrameCount -= 1
            inFlightFrameCount = max(inFlightFrameCount - 1, 0)
        }
        frameStateLock.unlock()
    }

    // DECLARED, BODY PINNED. init's tail call to this method is decoded (0x101a7c5c0, preset in
    // x0); the body itself is 156 instructions at 0x101a78b10 and was NOT read, so nothing is
    // written for it. It compiles as a no-op, which is a divergence its own unit must close.
    // ⚑[tool=function_extents ref=Anime4KPipeline.loadPreset:0x101a78b10 result=156-instr-unread]
    public func loadPreset(_: Anime4KPreset) {
        // UNRESOLVED → own unit: 0x101a78b10, 156 instr.
    }
}
