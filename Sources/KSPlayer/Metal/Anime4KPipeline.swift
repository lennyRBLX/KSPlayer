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
    public private(set) var inputTexture: MTLTexture?
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
        let storage = Unmanaged.passUnretained(self).toOpaque()
        storage.storeBytes(of: resolution, toByteOffset: 0x90, as: CGSize?.self)
        storage.storeBytes(of: false, toByteOffset: 0x88, as: Bool.self)
        storage.storeBytes(of: UInt8(2), toByteOffset: 0x31, as: UInt8.self)
    }

    // Body @0x101a7a34c, 6 instr, read in full — the same invalidation pair as above, against
    // maxUpscaleInputHeight (+0x28 value, +0x30 tag).
    public func updateUpscalePolicy(maxInputHeight: Int?) {
        let storage = Unmanaged.passUnretained(self).toOpaque()
        storage.storeBytes(of: maxInputHeight, toByteOffset: 0x28, as: Int?.self)
        storage.storeBytes(of: false, toByteOffset: 0x88, as: Bool.self)
        storage.storeBytes(of: UInt8(2), toByteOffset: 0x31, as: UInt8.self)
    }

    // Body @0x1003b9624, 2 instr, read in full: `ldrb w0, [x20, #0x31]` · `ret`. +0x31 is
    // cachedUpscaleSupport, and its nil tag is 2 — which is exactly what the two methods above
    // store to invalidate it.
    public func cachedUpscaleSupportStatus() -> Bool? {
        Unmanaged.passUnretained(self).toOpaque().load(fromByteOffset: 0x31, as: Bool?.self)
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
    public func isUpscaleSupported(pixelBuffer: any PixelBufferProtocol) -> Bool {
        if let maxUpscaleInputHeight, pixelBuffer.height > maxUpscaleInputHeight {
            return false
        }
        if anime4Ks.isEmpty {
            return false
        }
        let maxWidth = min(pixelBuffer.width * 2, 3840)
        let maxHeight = min(pixelBuffer.height * 2, 2160)
        _ = pixelBuffer.width
        _ = pixelBuffer.height
        let screen = anime4KScreenPixelSize()
        let target = overrideTargetResolution ?? CGSize(width: Double(screen.width), height: Double(screen.height))
        let fitted = anime4KAspectFit(target: target, pixelBuffer: pixelBuffer)
        let targetWidth = max(1, min(maxWidth, Int(fitted.width)))
        let targetHeight = max(1, min(maxHeight, Int(fitted.height)))
        if pixelBuffer.width < targetWidth {
            return true
        }
        return pixelBuffer.height < targetHeight
    }

    public func configure(pixelBuffer: any PixelBufferProtocol) -> CGSize? {
        videoWidth = pixelBuffer.width
        videoHeight = pixelBuffer.height

        guard (maxUpscaleInputHeight == nil || videoHeight <= maxUpscaleInputHeight!),
              !anime4Ks.isEmpty else {
            cachedUpscaleSupport = false
            configured = false
            supported = false
            inputTexture = nil
            return nil
        }

        supported = true
        let maxWidth = min(videoWidth * 2, 3840)
        let maxHeight = min(videoHeight * 2, 2160)
        let screen = anime4KScreenPixelSize()
        let requested = overrideTargetResolution
            ?? CGSize(width: screen.width, height: screen.height)
        let fitted = anime4KAspectFit(target: requested, pixelBuffer: pixelBuffer)
        let targetWidth = max(1, min(maxWidth, Int(fitted.width)))
        let targetHeight = max(1, min(maxHeight, Int(fitted.height)))

        cachedUpscaleSupport = videoWidth < targetWidth || videoHeight < targetHeight
        guard cachedUpscaleSupport == true else {
            configured = false
            supported = false
            inputTexture = nil
            return nil
        }

        if configured,
           videoWidth == compiledVideoWidth,
           videoHeight == compiledVideoHeight,
           targetWidth == compiledDisplayWidth,
           targetHeight == compiledDisplayHeight {
            return CGSize(width: targetWidth, height: targetHeight)
        }

        do {
            var runningWidth = videoWidth
            var runningHeight = videoHeight
            for anime4K in anime4Ks {
                try anime4K.configure(
                    device,
                    videoWidth,
                    videoHeight,
                    runningWidth,
                    runningHeight,
                    targetWidth,
                    targetHeight
                )
                runningWidth = Int(anime4K.outputW)
                runningHeight = Int(anime4K.outputH)
            }
            compiledVideoWidth = videoWidth
            compiledVideoHeight = videoHeight
            compiledDisplayWidth = targetWidth
            compiledDisplayHeight = targetHeight
            configured = true
            let descriptor = MTLTextureDescriptor()
            descriptor.width = videoWidth
            descriptor.height = videoHeight
            descriptor.pixelFormat = pixelBuffer.bitDepth == 10 ? .bgr10a2Unorm : .bgra8Unorm
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private

            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw Anime4KError.encoderFail("Failed to create input texture")
            }
            inputTexture = texture

            if let last = anime4Ks.last {
#sourceLocation(file: "KSPlayer/Anime4KPipeline.swift", line: 198)
                KSLog("[Anime4K] Configured: \(videoWidth)x\(videoHeight) -> \(Int(last.outputW))x\(Int(last.outputH)) (upscaled) -> \(targetWidth)x\(targetHeight) (display) with \(anime4Ks.count) shaders")
            }
            return CGSize(width: targetWidth, height: targetHeight)
        } catch {
            KSLog("[Anime4K] Configuration failed: \(error)")
#sourceLocation()
            configured = false
            supported = false
            inputTexture = nil
            return nil
        }
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
        let storage = Unmanaged.passUnretained(self).toOpaque()
        frameStateLock.lock()
        let inFlight = storage.load(fromByteOffset: 0x40, as: Int.self)
        let wasIdle = inFlight == 0
        if wasIdle {
            storage.storeBytes(of: Int(1), toByteOffset: 0x40, as: Int.self)
            let reserved = storage.load(fromByteOffset: 0x48, as: Int.self)
            storage.storeBytes(of: reserved + 1, toByteOffset: 0x48, as: Int.self)
        }
        frameStateLock.unlock()
        return wasIdle
    }

    // Body @0x101a78ac0, 20 instr, read in full. The guard is `subs x8, [x20,#0x48], #1` + `b.lt`,
    // so the block runs only when reservedFrameCount >= 1; the decrement reuses that same
    // subtraction. `bic x8, x8, x8, asr #63` is max(_, 0), and the unlock at 0x101a78b08 is a TAIL
    // CALL reached from both the taken and the skipped path.
    public func cancelFrameRendering() {
        let storage = Unmanaged.passUnretained(self).toOpaque()
        frameStateLock.lock()
        let reserved = storage.load(fromByteOffset: 0x48, as: Int.self)
        if reserved > 0 {
            storage.storeBytes(of: reserved - 1, toByteOffset: 0x48, as: Int.self)
            let inFlight = storage.load(fromByteOffset: 0x40, as: Int.self)
            storage.storeBytes(of: max(inFlight - 1, 0), toByteOffset: 0x40, as: Int.self)
        }
        frameStateLock.unlock()
    }

    // READ IN FULL. All 156 instructions of 0x101a78b10-0x101a78d80 are accounted for; the earlier
    // "NOT read" pin is discharged. vtable idx69. Exactly one exported symbol at the address
    // (unfolded), and the body's own KSLog literals independently confirm the member: `#file` =
    // 'KSPlayer/Anime4KPipeline.swift' (30) and `#function` = 'loadPreset(_:)' (14), the latter
    // also fixing the single UNLABELLED parameter.
    // ⚑[tool=export_trie_oracle ref=KSPlayer.Anime4KPipeline.loadPreset:0x101a78b10 result=OWNER_MATCH]
    //
    // STATEMENT ORDER IS LOAD-BEARING and is the binary's, not a preference:
    //   101a78b3c: strb w0, [x20, #0x20]   self.preset = preset      (BEFORE the guard)
    //   101a78b40: bl   0x101a78d80        build the shader-path list
    //   101a78b48: bl   0x101a79b84        loadShaderFiles(...)
    //   101a78b54: mov  w8, #0x2
    //   101a78b58: strb w8, [x20, #0x31]   cachedUpscaleSupport = nil (raw byte 2 = Optional.none)
    //   101a78b5c: cbz  w21, 0x101a78d34   `.disabled` -> the bare epilogue
    // The `.disabled` early exit sits AFTER all three side effects and skips ONLY the log, so it
    // cannot be hoisted to the top of the body. Offsets are named from this class's STATIC field
    // offset vector @0x1044ebe58 (preset 0x20, cachedUpscaleSupport 0x31, anime4Ks 0x18); note
    // `recover_field_offsets` refuses this class because every access is a constant immediate off
    // the self register, so there is no ivar-offset global to resolve.
    // ⚑[tool=field_offset_vector ref=Anime4KPipeline result=preset-0x20-cachedUpscaleSupport-0x31]
    //
    // THE SHADER LIST IS AN UNNAMED IMMEDIATELY-APPLIED CLOSURE: loadPreset `bl`s it (w0 = preset). The list is
    // built by 0x101a78d80, which is NOT_IN_TRIE; `name_exhaustion_gate` returns INLINE-INSTEAD on
    // it (1 call site image-wide), i.e. it has no independent identity and must NOT be given an
    // invented name. Its 58 instructions are a 13-arm jump table on the preset case index, read
    // from the byte table at 0x10356bee0 = 00 25 11 14 08 1a 1d 17 23 0e 20 05 0b scaled by 4 off
    // branch base 0x101a78db0 — 13 DISTINCT arms, no sharing, which is why no two cases are folded
    // into one `case .a, .b:` label below.
    // ⚑[tool=name_exhaustion_gate ref=anime4k_shader_list:0x101a78d80 result=INLINE-INSTEAD]
    //
    // Every path string is decoded with `decode_string_literal`, never read off a pointer value.
    // ⚠️ The stored `_object` word in each static array carries the `_StringObject.nativeBias`: the
    // real UTF-8 start is stored + 0x20, the INVERSE of the usual trap. Decoding at the stored
    // address yields NUL-crossing garbage. Verified end to end on case `.modeCAHQ` (object
    // 0x1044ec348: count 6, capacityAndFlags 12, six 16-byte String pairs all tagged 0xd000).
    // The `.disabled` arm loads `__swiftEmptyArrayStorage` and returns a genuinely empty array.
    // ⚑[tool=decode_string_literal ref=anime4k_shader_paths result=14-distinct-73-elements]
    public func loadPreset(_ preset: Anime4KPreset) {
        self.preset = preset
        let files: [String] = {
        switch preset {
        case .disabled:
            return []
        case .modeAFast:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_M.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_S.glsl"]
        case .modeBFast:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_Soft_M.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_S.glsl"]
        case .modeCFast:
            return ["Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_S.glsl"]
        case .modeAHQ:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_VL.glsl", "Upscale/Anime4K_Upscale_CNN_x2_VL.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl"]
        case .modeBHQ:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_Soft_VL.glsl", "Upscale/Anime4K_Upscale_CNN_x2_VL.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl"]
        case .modeCHQ:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl"]
        case .modeAAFast:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_M.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl", "Restore/Anime4K_Restore_CNN_S.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_S.glsl"]
        case .modeBBFast:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_Soft_M.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Restore/Anime4K_Restore_CNN_Soft_S.glsl", "Upscale/Anime4K_Upscale_CNN_x2_S.glsl"]
        case .modeCAFast:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Restore/Anime4K_Restore_CNN_S.glsl", "Upscale/Anime4K_Upscale_CNN_x2_S.glsl"]
        case .modeAAHQ:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_VL.glsl", "Upscale/Anime4K_Upscale_CNN_x2_VL.glsl", "Restore/Anime4K_Restore_CNN_M.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl"]
        case .modeBBHQ:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Restore/Anime4K_Restore_CNN_Soft_VL.glsl", "Upscale/Anime4K_Upscale_CNN_x2_VL.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Restore/Anime4K_Restore_CNN_Soft_M.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl"]
        case .modeCAHQ:
            return ["Restore/Anime4K_Clamp_Highlights.glsl", "Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl", "Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Restore/Anime4K_Restore_CNN_M.glsl", "Upscale/Anime4K_Upscale_CNN_x2_M.glsl"]
        } }()
        loadShaderFiles(files)
        cachedUpscaleSupport = nil
        if preset == .disabled {
            return
        }
        KSLog("[Anime4K] Loaded preset: \(preset.displayName) with \(anime4Ks.count) shaders", line: 110)
    }

    // DECLARED HERE, BODY PINNED — and the pin belongs to THIS member, not to `loadPreset` above.
    // vtable idx72, body @0x101a79b84, extent 0x101a79b84-0x101a7a34c, 1992 B / 498 instructions,
    // none of them read. It is a vtable slot, so it is not `private` (a private method on a
    // non-final class is statically dispatched and takes no slot); internal vs public is NOT
    // separable on this image, because the export trie carries ZERO `Tj` dispatch thunks of any
    // kind, so `Tj` absence discriminates nothing. The weaker spelling is written.
    //
    // The NAME is read, not invented: the body materializes its own `#function` literal
    // 'loadShaderFiles(_:)' (19 chars) alongside its `#file` companion 'KSPlayer/Anime4KPipeline.swift'
    // (30), and `recover_swift_function_name` returns it at high confidence with both anchors ok.
    // That is why this is a named declaration rather than a FUN_-address pin.
    // ⚑[tool=recover_swift_function_name ref=Anime4KPipeline.loadShaderFiles:0x101a79b84 result=high-confidence-#function]
    // ⚑[tool=export_trie_oracle ref=Anime4KPipeline.loadShaderFiles:0x101a79b84 result=NOT_IN_TRIE]
    // ⚑[tool=function_extents ref=Anime4KPipeline.loadShaderFiles:0x101a79b84 result=498-instr-unread]
    //
    // CONSEQUENCE, stated plainly: until these 498 instructions are read, `anime4Ks` stays empty and
    // `supported` stays false, so the KSLog above reports 0 shaders. `loadPreset` itself is now
    // faithful; this is where the remaining gap lives, and it is its own unit.
    func loadShaderFiles(_ files: [String]) {
        anime4Ks = []
        configured = false
        supported = false
        cachedUpscaleSupport = nil
        inputTexture = nil

        guard preset != .disabled, !files.isEmpty else {
            return
        }

        do {
            for path in files {
                let parts = path.split(separator: "/")
                guard parts.count == 2 else {
                    KSLog("[Anime4K] Invalid shader file path: \(path)")
                    continue
                }

                let anime4K = try Anime4K(
                    name: String(parts[1]),
                    url: String(parts[0]),
                    device: device,
                    usePrecompiled: true,
                    bufferCount: 1
                )
                anime4Ks.append(anime4K)
            }
        } catch {
            KSLog("[Anime4K] Failed to load shaders: \(error)")
            anime4Ks = []
        }
    }

    public func encode(commandBuffer: MTLCommandBuffer, outputTexture: MTLTexture) {
        frameStateLock.lock()
        if reservedFrameCount > 0 {
            reservedFrameCount -= 1
            frameStateLock.unlock()
            commandBuffer.addCompletedHandler { [weak self] _ in
                guard let self else { return }
                self.frameStateLock.lock()
                self.inFlightFrameCount = max(self.inFlightFrameCount - 1, 0)
                self.frameStateLock.unlock()
            }
        } else {
            frameStateLock.unlock()
        }

        guard supported,
              !anime4Ks.isEmpty,
              let inputTexture,
              configured else {
            if let inputTexture,
               let encoder = commandBuffer.makeBlitCommandEncoder() {
                encoder.copy(from: inputTexture, to: outputTexture)
                encoder.endEncoding()
            }
            return
        }

        let startTime = CACurrentMediaTime()
        do {
            var currentTexture = inputTexture
            for index in 0 ..< anime4Ks.count - 1 {
                currentTexture = try anime4Ks[index].encode(
                    device,
                    commandBuffer,
                    currentTexture
                )
            }
            try anime4Ks[anime4Ks.count - 1].encode(
                device,
                commandBuffer,
                currentTexture,
                outputTexture
            )
            commandBuffer.addCompletedHandler { [weak self] _ in
                guard let self else { return }
                self.updatePerformanceMetrics(
                    frameTime: CACurrentMediaTime() - startTime
                )
            }
        } catch {
#sourceLocation(file: "KSPlayer/Anime4KPipeline.swift", line: 345)
            KSLog("[Anime4K] Encode failed: \(error)")
#sourceLocation()
            if let encoder = commandBuffer.makeBlitCommandEncoder() {
                encoder.copy(from: inputTexture, to: outputTexture)
                encoder.endEncoding()
            }
        }
    }

    func updatePerformanceMetrics(frameTime: Double) {
        lastFrameTime = frameTime
        frameTimeHistory.append(frameTime)
        if frameTimeHistory.count > maxHistoryCount {
            frameTimeHistory.removeFirst()
        }

        if sustainedDropDetector(), !isDowngraded {
            isDowngraded = true
            onDowngradePreset?()
        }

        let slowFrameThreshold = 0.05
        guard frameTime > slowFrameThreshold else { return }
        let now = CACurrentMediaTime()
        guard now - lastPerformanceWarningTime >= 1.0 else { return }
        lastPerformanceWarningTime = now

        let recentCount = frameTimeHistory.filter { $0 > slowFrameThreshold }.count
        KSLog(
            "[Anime4K] Frame time: \(Int(frameTime * 1000))ms "
                + "(dropped frame, recent=\(recentCount)/\(frameTimeHistory.count))"
        )
    }

    // ⚑[invented=sustainedDropDetector addr=0x101a7b184 exhaustion=name_exhaustion_gate approved=jweaver]
    func sustainedDropDetector() -> Bool {
        guard frameTimeHistory.count >= 30 else { return false }
        return frameTimeHistory.filter { $0 > 0.05 }.count > 20
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
