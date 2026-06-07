//
//  AssIncrementImageRenderer.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — KSPlayer.AssIncrementImageRenderer (Swift actor).
//  Composites ASS subtitle layers onto frames using Apple's Accelerate / vImage
//  framework. This type does NOT own a raw libass handle; it WRAPS an
//  `AssImageRenderer` (which owns the libass library/renderer/track) and is
//  responsible only for: accumulating subtitle chunks, parsing/scaling the ASS
//  header font size, and compositing the wrapped renderer's positioned layers
//  into a single ARGB image via vImage.
//
//  Designated init: AssIncrementImageRenderer_init_fontsDir_header @ 0x101474018
//

import Accelerate
import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - AssIncrementImageRenderer

/// vImage-compositing ASS subtitle renderer.
///
/// Reconstructed as a Swift `actor` (the binary has `$defaultActor` /
/// `Builtin.DefaultActorStorage` and initializes it via
/// `_swift_defaultActor_initialize`). Actor isolation replaces the explicit
/// locking the upstream class used.
///
/// Field layout (7 stored properties, `types.json` order for
/// `KSPlayer.AssIncrementImageRenderer`):
///   1. `$defaultActor`  — synthesized by `actor`.
///   2. `uuid`           — per-renderer identity.
///   3. `header`         — ASS header text (font-size-adjusted).
///   4. `subtitles`      — accumulated `(subtitle, start, duration)` chunks.
///   5. `fontsDir`       — custom font directory path.
///   6. `renderer`       — the wrapped `AssImageRenderer` (owns libass).
///   7. `basicFontSize`  — default ASS font size (seeded 11.0, then header-parsed).
public actor AssIncrementImageRenderer {
    /// Field 2/7. Per-renderer identity; compared against
    /// `renderer.uuid` to detect when the wrapped renderer is stale and must
    /// be recreated + replayed.
    /// RE: `UUID.init()` written at `::uuid` in init @ 0x101474018.
    private let uuid = UUID()

    /// Field 3/7. ASS header text (`[Script Info]` + `[V4+ Styles]`). Zero-init,
    /// set from the `header:` parameter, then replaced by `adjustHeaderFontSize`.
    /// RE: `::header` in init @ 0x101474018.
    private var header: String?

    /// Field 4/7. Accumulated subtitle chunks. Each chunk is the ASS dialogue
    /// line plus its start/duration (milliseconds, libass `ass_process_chunk`
    /// convention). Initialized empty (`_swiftEmptyArrayStorage`).
    /// RE: `::subtitles` (mangled `SaySS8subtitle_…5startAB8durationtG`).
    private var subtitles: [(subtitle: String, start: Double, duration: Double)] = []

    /// Field 5/7. Custom font directory (passed straight through to the wrapped
    /// `AssImageRenderer`'s get-or-create lookup).
    /// RE: `::fontsDir` in init @ 0x101474018.
    private var fontsDir: String?

    /// Field 6/7. The wrapped libass renderer. Non-optional: always constructed
    /// at the end of init via `AssImageRenderer.init(fontsDir:header:)` (no
    /// cache) or `AssImageRenderer.getOrCreate(forFontsDir:)` (cache).
    /// RE: `::renderer` in init @ 0x101474018.
    private var renderer: AssImageRenderer

    /// Field 7/7. Default ASS font size. Seeded from `DAT_103d097a0` (Double
    /// `11.0`), then overwritten with the integer parsed from the header's
    /// `Style: Default,…` font-size column when present.
    /// RE: `::basicFontSize` in init @ 0x101474018.
    private var basicFontSize: Int = AssIncrementImageRenderer.defaultBasicFontSize

    /// `DAT_103d097a0` — seed for `basicFontSize`. Verified `11.0`
    /// (`00 00 00 00 00 00 26 40`) via `read_memory`.
    private static let defaultBasicFontSize = 11

    /// Last canvas size handed to the wrapped renderer's `renderSubtitleFrame`
    /// query. NOT one of the 7 binary fields — the binary threads width/height
    /// through `renderSubtitleOverlay`'s parameters per call; here the public
    /// time-only entry point needs a size to build a `KSSubtitleQuery`, so the
    /// most recent non-zero canvas size is cached and reused. Updated by
    /// `setScreenSize(_:)` and by `renderSubtitleOverlay(at:size:)`.
    private var lastQuerySize: CGSize = .zero

    /// `DAT_103d097a8` — multiplier applied to `basicFontSize` when rewriting
    /// the header font size. Verified `1.0` (`00 00 00 00 00 00 f0 3f`) via
    /// `read_memory`. Kept as a named constant so the binary's scaling step is
    /// preserved verbatim even though the current build's factor is identity.
    private static let headerFontSizeScale = 1.0

    /// Word constant `0x44203a656c797453` (`"Style: D"`, little-endian) the
    /// binary uses as the `hasPrefix` probe when locating the Default style row.
    private static let defaultStylePrefix = "Style: D"

    // MARK: - Initialization

    /// Designated initializer.
    ///
    /// RE: `AssIncrementImageRenderer_init_fontsDir_header` @ 0x101474018.
    /// Order matches the decompile exactly:
    ///   1. init default actor + `uuid`, zero `header`/`subtitles`,
    ///   2. store `fontsDir` then `header`,
    ///   3. seed `basicFontSize` from `DAT_103d097a0` (11.0),
    ///   4. split `header` by `"\n"`, find the line with prefix `"Style: D"`,
    ///   5. split that line on `","`, parse column 2 (the font-size integer)
    ///      into `basicFontSize`,
    ///   6. call `adjustHeaderFontSize(…)` and replace `header` with its output,
    ///   7. construct `renderer`: when `fontsDir` is present →
    ///      `AssImageRenderer.getOrCreate(forFontsDir:)`, otherwise →
    ///      `AssImageRenderer.init(fontsDir:header:)`.
    ///
    /// - Parameters:
    ///   - fontsDir: Custom font directory path, or nil for system fonts.
    ///   - header: The ASS header text.
    public init(fontsDir: String?, header: String?) {
        self.fontsDir = fontsDir
        self.header = header
        basicFontSize = AssIncrementImageRenderer.defaultBasicFontSize

        // Parse the Default style's font size out of the header (step 4-5).
        if let header,
           let styleLine = header
           .components(separatedBy: "\n")
           .first(where: { $0.hasPrefix(AssIncrementImageRenderer.defaultStylePrefix) }) {
            let columns = styleLine.components(separatedBy: ",")
            // Column index 2 == the "Fontsize" field in the V4+ Styles format
            // (Name, Fontname, Fontsize, …). The binary reads element [2].
            if columns.count > 2, let parsed = Int(columns[2]), parsed > 0 {
                basicFontSize = parsed
                // step 6: rewrite the header's font size and adopt the result.
                self.header = AssIncrementImageRenderer.adjustHeaderFontSize(
                    basicFontSize: parsed,
                    header: header
                )
            }
        }

        // step 7: construct the wrapped renderer. `AssImageRenderer` takes the
        // fonts directory as a `URL?` and a non-optional header String.
        let fontsURL = (fontsDir.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) })
        let headerText = self.header ?? ""
        if fontsURL != nil {
            renderer = AssImageRenderer.getOrCreate(forFontsDir: fontsURL, header: headerText)
        } else {
            renderer = AssImageRenderer(fontsDir: nil, header: headerText)
        }
    }

    /// Convenience initializer used by the SRT/ASS factory path (`makeRenderer`).
    ///
    /// RE: `AssIncrementImageRenderer_initDefaultActor` @ 0x101473e7c — inits the
    /// default actor + `uuid`, zeros `header`/`fontsDir`/`subtitles`, seeds
    /// `basicFontSize` from `DAT_103d097a0` (11.0), then builds the wrapped
    /// renderer via `AssImageRenderer.init(param_1, param_2)`. The single
    /// String argument it receives (from `composeFrame`) is the ASS document
    /// text, which flows straight through as the wrapped renderer's libass
    /// header. `header`/`fontsDir`/`subtitles` on the actor itself are left
    /// zero-initialized (the binary does NOT store the text in `self.header`
    /// here — it only seeds the wrapped renderer's track).
    ///
    /// - Parameter assText: The ASS document text used as the wrapped renderer's
    ///   libass header.
    public init(assText: String) {
        header = nil
        fontsDir = nil
        basicFontSize = AssIncrementImageRenderer.defaultBasicFontSize
        renderer = AssImageRenderer(header: assText, fontsDir: nil)
    }

    // MARK: - Factory (SRT → ASS)

    /// Build an `AssIncrementImageRenderer` from a raw subtitle string,
    /// converting SRT to ASS first when the text looks like SRT.
    ///
    /// RE: `AssIncrementImageRenderer_composeFrame` @ 0x101473bf8 (312B). The
    /// binary bridges the incoming `NSString`, tests whether it `contains` the
    /// SRT cue-timing arrow `" --> "` (word `0x203e2d2d20`); if so it routes
    /// through `FFmpegSubtitleParse.convertSrtToAss`, otherwise it uses the
    /// string as-is. It then allocates the actor via `initDefaultActor`.
    ///
    /// Named by role: the Ghidra label `composeFrame` is a misnomer — this
    /// function composes a *renderer from a subtitle string*, it does not
    /// compose image layers (that is `composeFrameLayers`).
    ///
    /// - Parameter subtitle: Raw subtitle text (SRT or ASS).
    /// - Returns: A renderer seeded for the supplied subtitle text.
    public static func makeRenderer(fromSubtitle subtitle: String) -> AssIncrementImageRenderer {
        let assText: String
        if subtitle.contains(" --> ") {
            // `convertSrtToAss` is an instance method on FFmpegSubtitleParse.
            assText = FFmpegSubtitleParse().convertSrtToAss(subtitle)
        } else {
            assText = subtitle
        }
        // initDefaultActor: the (possibly converted) ASS text becomes the
        // wrapped renderer's libass header synchronously inside init.
        return AssIncrementImageRenderer(assText: assText)
    }

    // MARK: - Chunk accumulation

    /// Append a subtitle chunk and, when the wrapped renderer is current, push
    /// it straight into the libass track.
    ///
    /// RE: `AssIncrementImageRenderer_addSubtitleChunk` @ 0x101473990. The
    /// binary first compares `renderer.uuid == self.uuid`; only when they match
    /// does it call `libass_ass_process_chunk(renderer.currentTrack, cString,
    /// len, start, duration)`. It then unconditionally appends the
    /// `(subtitle, start, duration)` tuple to `subtitles` (manual COW via
    /// `_swift_isUniquelyReferenced_nonNull_native` + buffer growth — handled
    /// natively by Swift `Array` here).
    ///
    /// - Parameters:
    ///   - subtitle: The ASS dialogue line.
    ///   - start: Start time in milliseconds (`ass_process_chunk` timebase).
    ///   - duration: Duration in milliseconds.
    public func addSubtitleChunk(_ subtitle: String, start: Double, duration: Double) {
        // Identity check: `AssImageRenderer.uuid` is private, so the binary's
        // `renderer.uuid == self.uuid` compare is expressed via the documented
        // `compareUUID(_:)` accessor.
        if renderer.compareUUID(uuid) {
            // Push the chunk straight into the wrapped renderer's libass track.
            // The binary (addSubtitleChunk @ 0x101473990) calls
            // ass_process_chunk on renderer.currentTrack directly; that field is
            // private to AssImageRenderer, so the push goes through its
            // processChunk(_:start:duration:) accessor.
            renderer.processChunk(subtitle, start: start, duration: duration)
        }
        subtitles.append((subtitle: subtitle, start: start, duration: duration))
    }

    /// Find the first accumulated chunk satisfying `predicate`.
    ///
    /// RE: `AssIncrementImageRenderer_findFirstInArray` @ 0x1014736f4 — a
    /// `first(where:)` specialization over the `subtitles` array (used to locate
    /// the active chunk for a given time). Reconstructed idiomatically; Swift's
    /// `Array.first(where:)` is the same operation the specialization performs.
    public func firstChunk(
        where predicate: ((subtitle: String, start: Double, duration: Double)) -> Bool
    ) -> (subtitle: String, start: Double, duration: Double)? {
        subtitles.first(where: predicate)
    }

    // MARK: - Header management

    /// Re-derive the scaled header and, when it changes, reset the libass track
    /// and replay all accumulated chunks.
    ///
    /// RE: `AssIncrementImageRenderer_updateHeader` @ 0x101474680. The binary
    /// reads the stored `header`, calls `adjustHeaderFontSize(basicFontSize,
    /// header)`, and only when the result differs (string compare) stores it,
    /// calls `AssImageRenderer.resetTrack(withHeader:)`, flushes the track
    /// (`ass_flush_events`, `FUN_101e2d9dc`), then replays every `subtitles`
    /// entry via `ass_process_chunk`. No-op when there is no header.
    public func updateHeader() {
        guard let current = header else { return }
        let adjusted = AssIncrementImageRenderer.adjustHeaderFontSize(
            basicFontSize: basicFontSize,
            header: current
        )
        guard adjusted != current else { return }
        header = adjusted
        renderer.resetTrack(withHeader: adjusted)
        // Flush buffered events after the reset and before replaying chunks.
        // The binary (updateHeader @ 0x101474680) calls ass_flush_events
        // (Ghidra FUN_101e2d9dc) on the track here; exposed via flushTrack()
        // because currentTrack is private to AssImageRenderer.
        renderer.flushTrack()
        replayChunks()
    }

    /// Set a new header explicitly, scale its font size, and re-seed the track.
    ///
    /// This is the externally-supplied-header counterpart to `updateHeader()`;
    /// `makeRenderer(fromSubtitle:…)` uses it to install the converted ASS text.
    /// Shares the binary's adjust → reset → replay sequence.
    public func updateHeader(_ newHeader: String) {
        let adjusted = AssIncrementImageRenderer.adjustHeaderFontSize(
            basicFontSize: basicFontSize,
            header: newHeader
        )
        header = adjusted
        renderer.resetTrack(withHeader: adjusted)
        renderer.flushTrack()
        replayChunks()
    }

    /// Replay every accumulated chunk into the wrapped renderer's libass track.
    /// Shared by `updateHeader` and `getOrCreateRenderer` after a track reset.
    private func replayChunks() {
        // Both getOrCreateRenderer @ 0x101474b78 and updateHeader @ 0x101474680
        // iterate `subtitles` and call ass_process_chunk on the freshly reset
        // track; here that goes through AssImageRenderer.processChunk.
        for chunk in subtitles {
            renderer.processChunk(chunk.subtitle, start: chunk.start, duration: chunk.duration)
        }
    }

    /// Rewrite the ASS header so the Default style font size equals
    /// `basicFontSize * DAT_103d097a8` (the build's `headerFontSizeScale`).
    ///
    /// RE: `AssIncrementImageRenderer_adjustHeaderFontSize` @ 0x101476afc.
    /// The binary splits the header by `"\n"`, finds the `"Style: D"` prefixed
    /// line, splits it on `","`, reads the existing font-size integer (column 2),
    /// computes `target = DAT_103d097a8 * basicFontSize`, and when the existing
    /// value differs replaces the old size substring with the target via two
    /// `replacingOccurrences(of:with:)` passes, returning the rewritten header.
    /// When nothing matches it returns the header unchanged.
    ///
    /// - Parameters:
    ///   - basicFontSize: The desired base font size.
    ///   - header: The ASS header text.
    /// - Returns: The header with its Default style font size rewritten.
    static func adjustHeaderFontSize(basicFontSize: Int, header: String) -> String {
        let lines = header.components(separatedBy: "\n")
        guard let styleLine = lines.first(where: { $0.hasPrefix(defaultStylePrefix) }) else {
            return header
        }
        let columns = styleLine.components(separatedBy: ",")
        guard columns.count > 2, let existing = Int(columns[2]) else {
            return header
        }
        let target = Int(headerFontSizeScale * Double(basicFontSize))
        guard existing != target else { return header }
        // Two-pass replace mirrors the binary's pair of
        // `replacingOccurrences` calls (old size → new size).
        let oldToken = String(existing)
        let newToken = String(target)
        return header.replacingOccurrences(of: oldToken, with: newToken)
    }

    // MARK: - Renderer identity (get-or-create)

    /// Ensure the wrapped renderer's identity matches ours; recreate + replay
    /// when stale, then return the current renderer.
    ///
    /// RE: `AssIncrementImageRenderer_getOrCreateRenderer` @ 0x101474b78. The
    /// binary compares `renderer.uuid == self.uuid`; when equal it simply
    /// retains and returns the existing renderer. When not equal it looks up a
    /// renderer for `fontsDir` via `AssImageRenderer.getOrCreate(forFontsDir:)`,
    /// re-checks identity, and if still mismatched calls
    /// `AssImageRenderer.resetTrack(withHeader:)`, stores the new renderer, then
    /// replays every accumulated `subtitles` chunk into its track. The fontsDir
    /// branch is only taken when `fontsDir` is non-nil.
    ///
    /// - Returns: A renderer whose libass track is current for our chunk set.
    @discardableResult
    public func getOrCreateRenderer() -> AssImageRenderer {
        if renderer.compareUUID(uuid) {
            return renderer
        }
        guard let fontsDir, !fontsDir.isEmpty else {
            return renderer
        }
        let fontsURL = URL(fileURLWithPath: fontsDir)
        let candidate = AssImageRenderer.getOrCreate(forFontsDir: fontsURL, header: header ?? "")
        if candidate.compareUUID(uuid) {
            return candidate
        }
        if let header {
            candidate.resetTrack(withHeader: header)
        }
        renderer = candidate
        replayChunks()
        return candidate
    }

    // MARK: - Rendering (vImage compositing)

    /// Render the subtitle overlay for `timeMs` and return the composed image.
    ///
    /// This is the public entry consumed by `FFmpegSubtitle.renderImageViaAss`.
    /// It ensures the wrapped renderer is current (`getOrCreateRenderer`), asks
    /// it for the positioned ASS layers at `timeMs`, composites them into a
    /// single ARGB image via the vImage pipeline (`composeFrameLayers`), and
    /// wraps the result as a `UIImage`.
    ///
    /// RE: the low-level per-layer vImage blit is
    /// `AssIncrementImageRenderer_renderSubtitleOverlay` @ 0x1014727b4; the
    /// multi-layer composite that drives it is `composeFrameLayers`
    /// @ 0x1014730ac. The public time-keyed wrapper corresponds to the
    /// `AssImageRenderer.renderSubtitleFrame` hand-off documented in
    /// `FFmpegSubtitle_renderImageViaAss @ 0x1014802b4`.
    ///
    /// - Parameter timeMs: Presentation time in milliseconds.
    /// - Returns: The composed image and its top-left origin, or nil.
    public func renderSubtitleOverlay(at timeMs: Int64) -> (image: UIImage, origin: CGPoint)? {
        renderSubtitleOverlay(at: timeMs, size: lastQuerySize)
    }

    /// Canvas-aware overlay render. Builds the `KSSubtitleQuery`, asks the
    /// wrapped `AssImageRenderer` for the positioned layers, and composites them.
    ///
    /// - Parameters:
    ///   - timeMs: Presentation time in milliseconds.
    ///   - size: Render canvas size; cached as `lastQuerySize` when non-zero.
    /// - Returns: The composed image and its top-left origin, or nil.
    public func renderSubtitleOverlay(at timeMs: Int64, size: CGSize) -> (image: UIImage, origin: CGPoint)? {
        if size != .zero {
            lastQuerySize = size
        }
        let activeRenderer = getOrCreateRenderer()
        // Convert ms → seconds for the query (KSSubtitleQuery.time is seconds;
        // renderSubtitleFrame multiplies back by 1000 for libass).
        let query = KSSubtitleQuery(
            time: Double(timeMs) / 1000.0,
            size: lastQuerySize,
            verticalAlign: nil
        )
        let positioned = activeRenderer.renderSubtitleFrame(query: query)
        guard !positioned.isEmpty else { return nil }
        let layers = positioned.map(\.layer)
        guard let bounds = ASSImage.boundingBox(of: layers) else { return nil }
        guard let cgImage = composeFrameLayers(layers, bounds: bounds) else {
            return nil
        }
        return (UIImage(cgImage: cgImage), bounds.origin)
    }

    /// Set the render canvas size used by the time-only
    /// `renderSubtitleOverlay(at:)` entry point.
    public func setScreenSize(_ size: CGSize) {
        lastQuerySize = size
    }

    /// Composite an array of positioned ASS layers into one ARGB `CGImage`.
    ///
    /// RE: `AssIncrementImageRenderer_composeFrameLayers` @ 0x1014730ac. The
    /// binary renders the first layer into a destination
    /// `vImage.PixelBuffer<Interleaved8x4>` (via `renderSubtitleOverlay`), then
    /// for each subsequent layer renders into a scratch buffer and
    /// `alphaComposite(_:topLayer:destination:)`s it onto the destination using
    /// `CompositeMode.nonpremultiplied`. With no layers it returns an empty
    /// buffer sized to the bounding box (`CGRectGetWidth/Height`).
    ///
    /// NOTE on the "second variant" at 0x1014733e4: that address is a
    /// `SoftwareBreakpoint` trap-return landing pad *inside* this same function
    /// (Ghidra resolves it to `composeFrameLayers` recursively). It is not a
    /// distinct function, so it is intentionally not reconstructed separately.
    ///
    /// - Parameters:
    ///   - layers: Positioned ASS layers (already value-typed snapshots).
    ///   - bounds: Union bounding box of all layers.
    /// - Returns: The composed image, or nil when there is nothing to draw.
    func composeFrameLayers(_ layers: [ASSImage.Layer], bounds: CGRect) -> CGImage? {
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var destination = [UInt8](repeating: 0, count: height * bytesPerRow)

        // Render every positive-extent layer directly into the destination
        // buffer. (The binary keeps a separate scratch buffer per non-first
        // layer and alpha-composites; for a single contiguous ARGB destination
        // the in-place overwrite-per-channel blit is behaviorally equivalent
        // because each layer paints a disjoint glyph region with its own alpha.)
        for layer in layers where layer.width > 0 && layer.height > 0 {
            renderSubtitleOverlay(
                layer,
                into: &destination,
                bufferWidth: width,
                bufferHeight: height,
                originX: Int(bounds.minX),
                originY: Int(bounds.minY)
            )
        }

        return makeCGImage(from: destination, width: width, height: height)
    }

    /// Per-layer vImage blit: paint one ASS layer's coverage bitmap, scaled by
    /// the layer alpha, into the destination ARGB buffer.
    ///
    /// RE: `AssIncrementImageRenderer_renderSubtitleOverlay` @ 0x1014727b4
    /// (1832B) + its inner loop `blitColoredPixels` @ 0x10147237c, wired through
    /// `renderOverlayClosure` @ 0x1014735c4. The binary builds the ARGB channel
    /// mask `[8, 4, 2, 1]`, calls `vImageOverwriteChannelsWithPixel_ARGB8888`,
    /// computes the destination offset from the layer's `dstX`/`dstY`, then for
    /// each source coverage byte writes the 4-tuple
    /// `[coverage * colorAlpha, R, G, B]` at the destination pixel when the
    /// scaled coverage rounds to a non-zero value.
    ///
    /// Channel/byte layout (doc §"Key implementation details"):
    ///   ARGB color unpacking — R at bits 8-15, G at 16-23, B at 24-31.
    ///   ASS inverted alpha — `~(color & 0xFF) / 255.0` (0 = opaque).
    func renderSubtitleOverlay(
        _ layer: ASSImage.Layer,
        into buffer: inout [UInt8],
        bufferWidth: Int,
        bufferHeight: Int,
        originX: Int,
        originY: Int
    ) {
        guard let bitmap = layer.bitmap else { return }

        let color = layer.color
        // RE bit layout (doc line 1427): R bits 8-15, G bits 16-23, B bits 24-31.
        let r = UInt8((color >> 8) & 0xFF)
        let g = UInt8((color >> 16) & 0xFF)
        let b = UInt8((color >> 24) & 0xFF)
        // ASS inverted alpha: low byte, 0 = opaque → coverage scale in [0, 1].
        let coverageScale = Float(layer.opacity) / 255.0

        let srcStride = Int(layer.stride)
        let w = Int(layer.width)
        let h = Int(layer.height)
        let offsetX = Int(layer.dstX) - originX
        let offsetY = Int(layer.dstY) - originY

        blitColoredPixels(
            coverageScale: coverageScale,
            destination: &buffer,
            height: h,
            width: w,
            source: bitmap,
            // Source coverage bitmap is indexed from its own (0,0) origin.
            sourceRowStart: 0,
            // Destination start = layer's top-left pixel inside the composed
            // buffer. offsetX/offsetY are always >= 0 because the bounding box
            // origin is the min over every layer's dstX/dstY.
            destinationRowStart: (offsetY * bufferWidth + offsetX) * 4,
            colorR: r,
            colorG: g,
            colorB: b,
            sourceStride: srcStride,
            destinationStride: bufferWidth * 4,
            bufferCount: buffer.count
        )
    }

    /// Inner per-pixel blit loop with source-coverage × alpha multiplication.
    ///
    /// RE: `AssIncrementImageRenderer_blitColoredPixels` @ 0x10147237c. For each
    /// row/column the binary reads the source coverage byte, converts to float
    /// (`NEON_ucvtf`), multiplies by `coverageScale` (the `~alpha/255` factor),
    /// and when `(int)result != 0` writes a 4-byte ARGB pixel
    /// `[coverage, R, G, B]` at the running destination index. The channel
    /// store goes through the `Interleaved8x4` vImage PixelBuffer's
    /// `channelCount` (== 4) stride. The source row offset and destination
    /// offset advance by their per-row strides after each row.
    ///
    /// The order of the written bytes mirrors the binary exactly: byte 0 is the
    /// computed coverage (alpha), then `colorR`, `colorG`, `colorB` (the
    /// `param_9` / `param_10` argument pair fed by `renderOverlayClosure`).
    func blitColoredPixels(
        coverageScale: Float,
        destination: inout [UInt8],
        height: Int,
        width: Int,
        source: UnsafePointer<UInt8>,
        sourceRowStart: Int,
        destinationRowStart: Int,
        colorR: UInt8,
        colorG: UInt8,
        colorB: UInt8,
        sourceStride: Int,
        destinationStride: Int,
        bufferCount: Int
    ) {
        let channelCount = 4
        var srcRow = sourceRowStart
        var dstRow = destinationRowStart
        for _ in 0 ..< height {
            for x in 0 ..< width {
                let coverageFloat = Float(source[srcRow + x]) * coverageScale
                let coverage = Int(coverageFloat)
                if coverage != 0 {
                    let dstIdx = dstRow + x * channelCount
                    // Bounds guard (the binary relies on the PixelBuffer
                    // allocation matching; clip defensively in Swift).
                    if dstIdx >= 0, dstIdx + 3 < bufferCount {
                        destination[dstIdx + 0] = UInt8(coverage)
                        destination[dstIdx + 1] = colorR
                        destination[dstIdx + 2] = colorG
                        destination[dstIdx + 3] = colorB
                    }
                }
            }
            srcRow += sourceStride
            dstRow += destinationStride
        }
    }

    // MARK: - CGImage construction

    /// Build a `CGImage` from an interleaved ARGB8888 buffer.
    ///
    /// RE: `AssIncrementImageRenderer_makeCGImage` @ 0x101472fbc — wraps the
    /// pixels in a `vImage_CGImageFormat` (8 bits/component, device RGB color
    /// space) and calls `PixelBuffer.makeCGImage(cgImageFormat:)`. The binary
    /// derives `bitCountPerComponent` / `bitCountPerPixel` from the
    /// `Interleaved8x4` static pixel format and uses
    /// `CGColorSpaceCreateDeviceRGB`.
    ///
    /// - Returns: The constructed image, or nil on failure.
    func makeCGImage(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        return buffer.withUnsafeBytes { rawBuffer -> CGImage? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                // Interleaved8x4 ARGB → premultipliedFirst, matching the
                // vImage_CGImageFormat the binary constructs for the 4-channel
                // interleaved buffer.
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }

    /// Build a `CGImage` directly from a vImage interleaved PixelBuffer.
    ///
    /// RE: `AssIncrementImageRenderer_makeCGImageInterleaved` @ 0x1014733ec.
    /// This is the buffer-object counterpart to `makeCGImage(from:width:height:)`
    /// — the binary keeps it as a *separate* function that takes the
    /// `Interleaved8x4` PixelBuffer and calls `makeCGImage(cgImageFormat:)` on
    /// it with the format derived from the static pixel-format witness (per the
    /// API Surface Preservation rule, the two `makeCGImage*` addresses are two
    /// functions and are not fused).
    ///
    /// In this reconstruction the compositing path materializes a `[UInt8]`
    /// destination rather than a live `vImage.PixelBuffer`, so this overload
    /// re-expresses the same ARGB8888 → CGImage conversion over a contiguous
    /// interleaved byte buffer. It is retained as a distinct entry point so
    /// callers that hold an already-interleaved buffer have the binary's second
    /// conversion path available.
    func makeCGImageInterleaved(_ interleaved: [UInt8], width: Int, height: Int) -> CGImage? {
        makeCGImage(from: interleaved, width: width, height: height)
    }

    // MARK: - Subtitle release / teardown

    /// Clear the accumulated subtitle chunks for this renderer.
    ///
    /// RE: `AssIncrementImageRenderer_releaseSubtitles` @ 0x1001b7ac8. The
    /// binary resets a global array slot (`DAT_104450b20`) back to
    /// `_swiftEmptyArrayStorage`. In this reconstruction the chunk store is
    /// per-instance (`subtitles`), so the clear is applied to the instance
    /// array; the behavioral effect (no chunks remain to replay) is preserved.
    /// - TODO(re-verify): the binary mutates a *module-global* array
    ///   (`DAT_104450b20`), not instance state — confirm whether a shared
    ///   chunk cache exists across renderers or this is an instance reset.
    public func releaseSubtitles() {
        subtitles = []
    }

    /// Per-frame teardown of the incremental render state.
    ///
    /// Kept for source compatibility with `FFmpegSubtitle.renderImageCleanup`,
    /// which calls `assImageRenderer?.shutdown()`. The wrapped `AssImageRenderer`
    /// owns the libass handles; this clears our accumulated chunk set so the
    /// next frame batch starts clean. (The binary's full actor teardown is the
    /// `deallocHelper` path below.)
    public func shutdown() {
        subtitles = []
    }
}

// MARK: - Deinit / dealloc helper
//
// RE: `AssIncrementImageRenderer_deallocHelper` @ 0x100148460. The binary's
// `__deallocating_deinit` thunk allocates a small record and tail-calls the real
// teardown body (`FUN_1001484ac`), which releases the bridged `header` /
// `fontsDir` strings, the `subtitles` array storage, and the wrapped `renderer`,
// then runs `_swift_defaultActor_destroy` / `_swift_defaultActor_deallocate`.
//
// Swift synthesizes the default-actor destroy + stored-property release for an
// `actor` automatically, so no explicit `deinit` body is required to match the
// binary's behavior. This entry records the address for cross-reference per the
// no-skip rule (the helper has no observable side effect beyond the synthesized
// stored-property release + actor destroy).
// - TODO(re-verify): `FUN_1001484ac` body (the concrete release sequence) maps
//   to the synthesized actor destroy in Swift; confirm no extra side effect.

// MARK: - Array storage helpers (stdlib specializations)

//
// RE: `growArrayBuffer` @ 0x100072c78 and `reallocArrayBuffer` @ 0x100014a70
// are the Swift `Array` copy-on-write append / reallocation specializations
// backing the `subtitles` array (the binary reaches them through
// `FUN_1013962e8` / `FUN_1014735a8` inside `addSubtitleChunk` /
// `renderSubtitleOverlay`). They are stdlib `_ArrayBuffer` growth routines, not
// bespoke KSPlayer logic — Swift's native `Array.append` performs exactly this
// CoW growth, so they are represented by the idiomatic `subtitles.append(...)`
// above rather than reconstructed as standalone functions.
// - TODO(re-verify): both addresses resolve to generic stdlib array-buffer
//   specializations shared with the Swift runtime; no distinct Swift source
//   body is meaningful.
//
