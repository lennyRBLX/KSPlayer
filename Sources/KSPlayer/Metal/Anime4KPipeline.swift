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
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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

    /// ⚑[tool=export_trie_oracle ref=KSPlayer.Anime4KPipeline.isUpscaleSupported(pixelBuffer:):0x101a7a364 result=152-instr]
    /// Read in full. Every field offset is resolved by `field_offset_vector` (this class's vector is
    /// static and fully decoded), so `+0x28`/`+0x30`/`+0x18`/`+0x90`/`+0xa0` are read, not matched
    /// by position; every witness slot is resolved by position in `PixelBufferProtocol`'s declared
    /// requirement order — `wt+0x8` = `width`, `wt+0x10` = `height`, `wt+0x38` = `aspectRatio`
    /// (slot 6, the first requirement returning a CGSize, which is why it comes back in d0/d1).
    ///
    /// · The first guard reads the Optional's TAG, not its value: `ldrb w8, [x22, #0x30]` with
    ///   `cmp w8, #1` skipping the check. `+0x28` is `maxUpscaleInputHeight`'s payload and `+0x30`
    ///   its tag, so tag 1 is `nil`. The comparison is `b.ge` on `(maxUpscaleInputHeight, height)`,
    ///   i.e. fall through only when the height fits.
    /// · `anime4Ks.isEmpty` is the array count feeding straight into the return: `cbz x0` jumps to
    ///   the epilogue with x0 STILL holding the count, so the zero count IS the returned `false`.
    /// · `*2` carries a real overflow trap (`cmn x0, #1<<62` / `b.mi` → `brk`), so it is a checked
    ///   multiply, not a shift.
    ///
    /// ⚑ The last two `min` pairs look like three-way selects but are not: `x26` is already
    ///   `min(width * 2, 3840)`, so the `Int(fitted.width) > 3840` arm and the `min` arm agree.
    ///   The compiler emitted both sides of the comparison; the source is one `min`.
    func isUpscaleSupported(pixelBuffer: any PixelBufferProtocol) -> Bool {
        if let maxUpscaleInputHeight, pixelBuffer.height > maxUpscaleInputHeight {
            return false
        }
        if anime4Ks.isEmpty {
            return false
        }
        let maxWidth = min(pixelBuffer.width * 2, 3840)
        let maxHeight = min(pixelBuffer.height * 2, 2160)
        let screen = anime4KScreenPixelSize()
        let target = overrideTargetResolution ?? CGSize(width: Double(screen.width), height: Double(screen.height))
        let fitted = anime4KAspectFit(target: target, pixelBuffer: pixelBuffer)
        let targetWidth = max(1, min(maxWidth, Int(fitted.width)))
        if pixelBuffer.width < targetWidth {
            return true
        }
        let targetHeight = max(1, min(maxHeight, Int(fitted.height)))
        return pixelBuffer.height < targetHeight
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

    /// ⚑[tool=export_trie_oracle ref=Anime4KPipeline.getPerformanceStats():0x101a7b2a8 result=59-instr]
    /// Every one of the four fields it touches is resolved BY NAME out of this class's own field
    /// offset vector (@0x1044ebe58), not inferred from the access sites:
    /// `preset` @0x20 · `supported` @0x89 · `lastFrameTime` @0xa8 · `frameTimeHistory` @0xb0.
    /// ⚑[tool=field_offset_vector ref=Anime4KPipeline result=preset@0x20,supported@0x89,lastFrameTime@0xa8,frameTimeHistory@0xb0]
    ///
    /// The body sums `frameTimeHistory` under a read access — unrolled four-wide with `ldp q2,q3`
    /// plus a scalar tail, which is what `reduce(0, +)` lowers to — then `ucvtf` the count and
    /// `fdiv` for the mean. `estimatedFPS` is `fmov d2,#1.0` / `fdiv d2,d2,d1` guarded by
    /// `fcmp d1,#0.0` / `fcsel …,gt`, i.e. reciprocal-of-mean only when the mean is positive.
    ///
    /// ⚑ The RETURN is register-packed, and that is how the last three fields are pinned. Three
    ///   Doubles go in d0/d1/d2 — `lastFrameTime`, the mean, the FPS — and the trailing scalars
    ///   are folded into w0 at fixed bit positions:
    ///     bit 0  ← `cinc w8, w8, gt` from `fcmp d0, 0.033`  → `isDropping`
    ///     bit 8  ← `mov w8,#0x100` / `csel` on `supported`  → `supported`
    ///     bit 16 ← `orr w0, w8, w9, lsl #16` from `[x20,#0x20]` → `preset`
    ///   That ordering matches Anime4KPerformanceStats' declaration exactly, which is what makes
    ///   the mapping a reading rather than a guess.
    /// ⚑ 0.033 is READ from the constant pool at 0x1035647c8, not assumed from "30fps".
    ///
    /// ⚑ An empty history yields mean 0 AND fps 0: the `cbz` skips both the sum and the divide,
    ///   and the `fcsel` then rejects the `1.0/0` infinity. Spelling it with `isEmpty` reproduces
    ///   that; a bare `sum / count` would give NaN.
    /// ⚑ AMBIGUOUS: `isEmpty ? 0 : …` and an `if !isEmpty { }` over a `var` lower identically.
    public func getPerformanceStats() -> Anime4KPerformanceStats {
        let average = frameTimeHistory.isEmpty
            ? 0
            : frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
        return Anime4KPerformanceStats(
            lastFrameTime: lastFrameTime,
            averageFrameTime: average,
            estimatedFPS: average > 0 ? 1 / average : 0,
            isDropping: lastFrameTime > 0.033,
            supported: supported,
            preset: preset
        )
    }
}

/// ⚑[tool=recover_swift_function_name ref=0x101a7c2e4 result=NOT_IN_TRIE-no-#function-literal]
/// A FREE function, not a method: the body at 0x101a7c2e4 (74 instr, read in full) never touches
/// a self register and takes no arguments. It is `private`, so it has no export-trie symbol and
/// `recover_swift_function_name` finds no `#function` literal — **the NAME above is therefore
/// invented, and only the name is.** Everything else is read:
///   · classref 0x1044108c8 = `UIScreen`
///     ⚑[tool=bind_oracle ref=__objc_classrefs:0x1044108c8 result=_OBJC_CLASS_$_UIScreen]
///   · three sends, decoded from their selrefs, in this order:
///     ⚑[tool=decode_objc_selector ref=0x10440c0f0 result='mainScreen']
///     ⚑[tool=decode_objc_selector ref=0x10440a900 result='bounds']
///     ⚑[tool=decode_objc_selector ref=0x10440cca0 result='scale']
///     `bounds` returns a CGRect, so its size lands in d2/d3 — which is exactly the pair the
///     multiply consumes; `mainScreen` is sent twice because the two reads are not CSE'd.
///   · `frinta` is round-half-away-from-zero = Swift's `.rounded()`, NOT `floor`/`trunc`; the
///     `fmaxnm _, #1.0` after it is the `max(1, …)`. `fcvtzs` plus the ±2^63 guards
///     (`0xc3e0…`/`0x43e0…`) and the `0x7fef…` finite check are the `Int(_:)` conversion traps.
/// ⚑ THE `#else` BRANCH IS NOT IN THIS IMAGE. Forward-TF is an iOS binary, so only the UIKit arm
///   has bytes to read; the AppKit arm is the mechanical counterpart (`NSScreen.frame` +
///   `backingScaleFactor` are the direct analogues of `bounds` + `scale`) and is written to keep
///   the macOS target building, NOT because it was recovered. Whether Forward's source guarded
///   this at all is undecidable from an iOS-only image. Re-derive it if a macOS build ever lands.
private func anime4KScreenPixelSize() -> (width: Int, height: Int) {
    #if canImport(UIKit)
    let bounds = UIScreen.main.bounds
    let scale = UIScreen.main.scale
    #else
    let bounds = NSScreen.main?.frame ?? .zero
    let scale = NSScreen.main?.backingScaleFactor ?? 1
    #endif
    return (Int(max((bounds.width * scale).rounded(), 1)), Int(max((bounds.height * scale).rounded(), 1)))
}

/// ⚑[tool=recover_swift_function_name ref=0x101a7c40c result=NOT_IN_TRIE-no-#function-literal]
/// Also a FREE private function (68 instr @0x101a7c40c, read in full) — it takes only the
/// existential and the target size, never a self register. **The NAME is invented; the body is
/// read.** It aspect-fits `target` to the buffer's DISPLAY ratio:
///   · `wt+0x38` is `aspectRatio` (CGSize), so it returns in d0/d1, and each component is
///     independently replaced by 1.0 when non-positive — two `fcsel` pairs that compute the same
///     predicate, which is the compiler emitting both sides of one comparison.
///   · ratio = (sar.width * Double(width)) / (sar.height * Double(height)).
///   · A non-finite ratio returns `target` UNCHANGED — the `0x7fef…` compare branches straight to
///     the epilogue with v8/v9 still holding the inputs. That early-out is the reason the guard
///     below is a `guard`, not an `if` around the whole computation.
/// ⚑ The `ratio >= 1` split is in the BINARY, and both arms compute the same result — fit by the
///   long edge, fall back to the other. It is kept because collapsing it would not reproduce the
///   two branch targets at 0x101a7c500 and 0x101a7c4e4.
private func anime4KAspectFit(target: CGSize, pixelBuffer: any PixelBufferProtocol) -> CGSize {
    let aspect = pixelBuffer.aspectRatio
    let sarWidth = aspect.width > 0 ? aspect.width : 1
    let sarHeight = aspect.height > 0 ? aspect.height : 1
    let ratio = (sarWidth * Double(pixelBuffer.width)) / (sarHeight * Double(pixelBuffer.height))
    guard ratio.isFinite else {
        return target
    }
    let width = max(target.width, 1)
    let height = max(target.height, 1)
    if ratio >= 1 {
        let fitted = width / ratio
        return fitted <= height ? CGSize(width: width, height: fitted) : CGSize(width: height * ratio, height: height)
    } else {
        let fitted = height * ratio
        return fitted <= width ? CGSize(width: fitted, height: height) : CGSize(width: width, height: width / ratio)
    }
}
