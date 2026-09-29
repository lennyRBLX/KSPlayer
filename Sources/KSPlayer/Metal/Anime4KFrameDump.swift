//
//  Anime4KFrameDump.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction (partial). `Anime4KFrameDump` is a feature-toggled, rate-limited
//  GPU frame-export facility — part of the (otherwise un-reconstructed) Anime4K real-time-upscaling
//  subsystem. `MetalRender.draw` integrates it: when enabled and under the rate limit it reads back
//  the rendered frame texture and exports numbered files to <Documents>/Anime4KDump.
//
//  THIS COMMIT = the enum + its static STATE only (floor-neutral declaration; MetalRender static-
//  storage precedent). The 4 static methods follow in later commits:
//    configure(…) @0x101a775c0 · gate @0x101a784d4 · async-notify @0x101a778a8 · readback @0x101a77d20
//
//  Owner identified deterministically (s52): the default-dir builder @0x101a76f44 appends the
//  "Anime4KDump" literal; catalog types_1.3.17.json lists `Anime4KFrameDump` (enum, KSPlayer). All
//  property names WERE inferred (`#function` yielded nothing) and FIVE OF THEM WERE WRONG — the
//  orphaned export trie names every public static directly. TYPES + storage are decoded from the
//  module globals + swift_once inits. Full map: reconstruction/draw_preflight_session52.json.
//
//  RECOVERED session 63 (each type independently corroborates the pairing):
//    isEnabled -> enabled (Bool) · frameLimit -> maxFrames (Int) · directory -> outputDirectory (URL)
//    notifyEnabled -> dumpDecoded (Bool) · readbackEnabled -> dumpRendered (Bool)
//  All five carry a `property descriptor` (vpMV), which is public-exclusive, so all five are
//  `public` — previously only `isEnabled` was.
// ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.{enabled,maxFrames,outputDirectory,dumpDecoded,dumpRendered} result=NAMES+ACCESS RECOVERED, superseding "all property names INFERRED"]
//

import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

public enum Anime4KFrameDump {
    /// Master enable toggle. Storage DAT_104c636c0; direct setter @0x101a76c08 (no once-guard).
    public nonisolated(unsafe) static var enabled = false

    /// Frames exported so far; reset to 0 by configure, incremented under `stateLock` in the gate
    /// @0x101a784d4 (dumps only while frameCounter < maxFrames). Storage DAT_1044ebcf0.
    /// ⚑ name still INFERRED — and now a VERIFIED negative: this static carries no symbol in the
    ///   export trie, consistent with it not being public (the five above all do).
    // ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.frameCounter result=absent — VERIFIED negative, name remains inferred]
    nonisolated(unsafe) static var frameCounter = 0

    /// Sub-toggle gating the async-notify path (@0x101a778a8). Storage DAT_1044ebcc8.
    public nonisolated(unsafe) static var dumpDecoded = false

    /// Sub-toggle gating the GPU texture-readback path (@0x101a77d20). Storage DAT_1044ebcc9.
    public nonisolated(unsafe) static var dumpRendered = false

    /// Max frames to export; set by configure @0x101a775c0. Storage DAT_1044ebcd0.
    public nonisolated(unsafe) static var maxFrames = 0

    /// Export directory (lazy). Storage DAT_104c636c8; default builder @0x101a76f44. configure can
    /// override.
    public nonisolated(unsafe) static var outputDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Anime4KDump")
    }()

    /// Public config entry. The method name and ALL FIVE parameter labels are RECOVERED, not
    /// inferred — `recover_swift_function_name` returned None here, but the orphaned export trie
    /// carries the full mangled name. Every one of the five inferred labels was wrong.
    /// ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.configure(enabled:maxFrames:outputDirectory:dumpDecoded:dumpRendered:) result=labels RECOVERED, superseding the `recover_swift_function_name ref=0x101a775c0 result=None` pin]
    /// Sets the enable flag, the frame limit and the two sub-toggles, optionally overrides the export
    /// directory, and resets the frame counter under `stateLock`. Reconstructed from @0x101a775c0.
    public static func configure(enabled: Bool, maxFrames: Int, outputDirectory: URL?, dumpDecoded: Bool, dumpRendered: Bool) {
        Anime4KFrameDump.enabled = enabled
        Anime4KFrameDump.maxFrames = maxFrames
        if let outputDirectory {
            Anime4KFrameDump.outputDirectory = outputDirectory
        }
        Anime4KFrameDump.dumpDecoded = dumpDecoded
        Anime4KFrameDump.dumpRendered = dumpRendered
        stateLock.lock()
        frameCounter = 0
        stateLock.unlock()
    }

    /// Serializes `frameCounter`. Lazy = NSLock() (once-init @0x101a77598). Storage DAT_1044ebce8.
    /// THE ABSENCE IS NOW MEASURED, NOT PREDICTED. The note here used to read "absent from the trie,
    /// as expected for a non-public static" — a prediction, and this session has found four such
    /// notes to be false. Measured in BOTH directions and BOTH mangling shapes: 0x101a77598 exports
    /// no symbol; the class's full trie subtree is 32 symbols covering only dumpDecoded, dumpRendered,
    /// outputDirectory, enabled, maxFrames, reset() and configure(...); and a raw scan of all 57138
    /// trie symbols finds no `Anime4KFrameDump…33_<32hex>LL…` of any kind.
    /// TWO POSITIVE CONTROLS make that a real negative rather than a blind spot: the five public
    /// statics' storage globals DO resolve by address (0x1044ebcc8 → …dumpDecodedSbvpZ etc.), and the
    /// sibling `Anime4KPipeline` carries 20 file-private `33_DF46…LL` symbols — so this image DOES
    /// emit the private mangling when the member exists. Storage 0x1044ebce8 and token 0x1044ebce0
    /// both resolve to nothing.
    /// ⚑[invented=stateLock addr=0x101a77598 exhaustion=name_exhaustion_gate approved=jweaver]
    static let stateLock = NSLock()

    /// Serial queue for the export work. Lazy (once-init @0x101a773cc: label "Anime4KFrameDump",
    /// default qos, empty attributes → serial). Storage DAT_1044ebd00, token 0x1044ebcf8.
    /// Absence from the trie measured exactly as for `stateLock` above, same controls.
    /// ⚠️ `recover_swift_function_name` reports `#function: Anime4KFrameDump (confidence=high)` for
    /// 0x101a773cc. THAT IS A FALSE ANCHOR: the literal is the `label:` ARGUMENT consumed by
    /// `DispatchQueue.init(label:qos:attributes:autoreleaseFrequency:target:)`, not a `#function`
    /// default — the same (x0,x1) pair is passed straight into the initializer, and there is no
    /// `#file` companion. A bare `#function` candidate with no `#file` is data, not a name.
    /// The label's true bytes are at 0x10356be90 (count 16); the `sub x19, x8, #0x20` is the
    /// nativeBias trap, and reading the biased 0x10356be70 yields garbage.
    /// ⚑[invented=queue addr=0x101a773cc exhaustion=name_exhaustion_gate approved=jweaver]
    static let queue = DispatchQueue(label: "Anime4KFrameDump")

    // 🚨 DO NOT ACT ON `name_exhaustion_gate`'s INLINE-INSTEAD VERDICT FOR EITHER OF THE TWO ABOVE.
    //   It reports "0 call site(s) image-wide → inline the expression at the call site rather than
    //   naming it". Both are `swift_once` ONE-TIME-INIT bodies: they are never `bl`-called, they are
    //   passed BY ADDRESS to `swift_once` (0x101a77598 at three sites, 0x101a773cc at two —
    //   e.g. `adrp x1, 0x101a77000 / add x1, x1, #0x598 / bl 0x10345cfa0` where 0x10345cfa0 binds
    //   `_swift_once`). The gate's single-call-site route counts only `bl` targets, so its zero is an
    //   ARTIFACT of the scan, and acting on the verdict would DELETE a real member.

    /// ⚑[tool=export_trie_oracle ref=Anime4KFrameDump.reset():0x101a7783c result=23-instr]
    /// The decompile unit the previous marker here asked for. Nothing is guessed:
    ///
    ///   · `swift_once(&0x1044ebce0, 0x101a77598)` (__got 0x104113018) then load `[0x1044ebce8]`.
    ///     That token/initializer PAIR is the same one `configure` below uses @0x101a7780c, which
    ///     is what identifies the object as `stateLock` rather than `queue` — both are lazy
    ///     `static let`s and only the shared once-token distinguishes them.
    ///   · two ObjC sends on it, decoded from their selrefs: `lock` (0x10440c080) and `unlock`
    ///     (0x10440e750, reached as a tail-call).
    ///     ⚑[tool=decode_objc_selector ref=0x10440c080 result='lock']
    ///   · between them, one `str xzr, [0x1044ebcf0]` — a 64-bit zero store.
    ///
    /// ⚑ WHICH Int static that is, is settled by ELIMINATION rather than by name or adjacency:
    ///   this type has exactly two `Int` statics, and `configure` writes `maxFrames` at
    ///   **0x1044ebcd0** (`str x27` after its own begin-access). `reset` writes **0x1044ebcf0**, a
    ///   different global, leaving `frameCounter` as the only candidate.
    ///
    /// ⚑ Corroboration, not derivation: `configure` below already ends with this exact
    ///   lock/zero/unlock triple, reconstructed in an earlier session from its own body. `reset()`
    ///   is that block standing alone.
    public static func reset() {
        stateLock.lock()
        frameCounter = 0
        stateLock.unlock()
    }

    // L7 lane 15. The four bodies below carry no trie symbol (internal; no private discriminator seen).
    // .o order: reset 0x101a7783c < dumpDecoded 0x101a778a8 < dumpRendered 0x101a77d20 < gate 0x101a784d4
    // < PNG writer 0x101a78640. Called by both MetalRender draw helpers (0x101a873b4, 0x101a86090).

    // Forward 0x101a778a8 (167 insns): args x0/x1 = pixelBuffer existential, x2 = frameIndex. Reads
    // `enabled` 0x104c636c0 then `dumpDecoded` 0x1044ebcc8 (beginAccess each), `cgImage()` = wt+0x120 @0x101a779a4,
    // then `queue.async` with context {frameIndex @+0x10, image @+0x18} (`stp x24,x20,[x0,#0x10]` @0x101a779e0),
    // body 0x101a77b44 via partial apply 0x101a77cfc. Format literal 0x103d37550 "decoded_%04d.png".
    static func dumpDecodedFrame(pixelBuffer: PixelBufferProtocol, frameIndex: Int) { // INFERRED
        guard enabled, dumpDecoded, let image = pixelBuffer.cgImage() else {
            return
        }
        queue.async {
            let url = outputDirectory.appendingPathComponent(String(format: "decoded_%04d.png", frameIndex))
            writePNG(image, to: url)
        }
    }

    // Forward 0x101a77d20 (143 insns): args x0 = texture, x1 = commandBuffer, x2 = frameIndex. Pixel-format
    // gate `sub x8,x0,#0x46; cmp x8,#0xb; mov w9,#0xc03; tst` @0x101a77da4 = raw 70/71/80/81. width*4 overflow
    // check @0x101a77ddc, `mul/smulh` length @0x101a77df8, `newBufferWithLength:options:` x3=0 @0x101a77e24,
    // blit copy @0x101a77e84 (origin 0, size {w,h,1}, offset 0), endEncoding, addCompletedHandler @0x101a77f14.
    // Completion context (0x48) {buffer, length, width, height, bytesPerRow, pixelFormat, frameIndex}
    // @0x101a77ea4..b0; completion body 0x101a77f5c re-captures the same 7 into `queue.async`
    // (partial apply 0x101a788dc → body 0x101a781a4).
    static func dumpRenderedFrame(texture: MTLTexture, commandBuffer: MTLCommandBuffer, frameIndex: Int) { // INFERRED
        guard enabled, dumpRendered else {
            return
        }
        let pixelFormat = texture.pixelFormat
        switch pixelFormat {
        case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb:
            break
        default:
            return
        }
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let length = bytesPerRow * height
        guard let buffer = texture.device.makeBuffer(length: length, options: .storageModeShared),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        else {
            return
        }
        blitEncoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                         sourceSize: MTLSize(width: width, height: height, depth: 1),
                         to: buffer, destinationOffset: 0,
                         destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: length)
        blitEncoder.endEncoding()
        commandBuffer.addCompletedHandler { _ in
            queue.async {
                // Body 0x101a781a4: Data(bytes:count:) 0x100036e98 from `contents` @0x101a78254,
                // CGColorSpaceCreateDeviceRGB @0x101a78260, one [CGBitmapInfo] stack literal picked by
                // `(pixelFormat & ~1) == 0x50` (pairs {0x2000,2}/{0x4000,1} at 0x1035647b0/0x1035647c0) folding to
                // `csel w6, 0x2002, 0x4001` @0x101a782f8; CGImageCreate(8, 32, decode nil, interpolate 1, intent 0).
                // pixelFormat is captured after bytesPerRow, so its first use sits in the CGImage argument list.
                // Format literal 0x103d37570 "rendered_%04d.png" (count 0x11 @0x101a783e8).
                let data = Data(bytes: buffer.contents(), count: length)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let provider = CGDataProvider(data: data as CFData),
                      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                          bytesPerRow: bytesPerRow, space: colorSpace,
                                          bitmapInfo: pixelFormat == .bgra8Unorm || pixelFormat == .bgra8Unorm_srgb
                                              ? [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)]
                                              : [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)],
                                          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                else {
                    return
                }
                let url = outputDirectory.appendingPathComponent(String(format: "rendered_%04d.png", frameIndex))
                writePNG(image, to: url)
            }
        }
    }

    // Forward 0x101a784d4 (91 insns): arg x0 = address of `VideoPipeline?`; returns Int? (x0, w1 nil flag).
    // `enabled` beginAccess + `cmp w8,#1` @0x101a7850c; Optional copy 0x10002e588, nil → destroy 0x10003751c;
    // swift_dynamicCast flags 6 to Anime4KPipeline (accessor 0x101a7c88c) @0x101a7856c, result released.
    // stateLock (token 0x1044ebce0) lock; frameCounter 0x1044ebcf0 read with no beginAccess; `maxFrames`
    // beginAccess @0x101a785bc; `b.ge` @0x101a785c8; `add x9,x22,#1; str` then unlock, return old value.
    static func nextFrameIndex(pipeline: VideoPipeline?) -> Int? { // INFERRED
        guard enabled, pipeline is Anime4KPipeline else {
            return nil
        }
        stateLock.lock()
        let index = frameCounter
        if index < maxFrames {
            frameCounter = index + 1
            stateLock.unlock()
            return index
        }
        stateLock.unlock()
        return nil
    }

    // Forward 0x101a78640 (153 insns): args x0 = CGImage, x1 = URL (indirect). `createDirectory(at:
    // withIntermediateDirectories:attributes:)` on a copy of `outputDirectory`; on error only
    // swift_errorRelease then return. CGImageDestinationCreateWithURL(url, UTType.png.identifier, 1, nil),
    // AddImage(dest, image, nil), Finalize.
    static func writePNG(_ image: CGImage, to url: URL) { // INFERRED
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
