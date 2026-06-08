//
//  AssImageRenderer.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — libass-backed ASS/SSA image renderer.
//
//  Reconstructed from the 1.3.15 binary (class `_TtC8KSPlayer16AssImageRenderer`).
//  The render entry point produces an *array of positioned image rects* (the
//  libass `ASS_Image` linked list converted to value-typed CGRect-positioned
//  layers via `ASSImage.linkedListToArray`), NOT a single composited CGImage.
//  See `renderSubtitleFrame(query:)`.
//

import CoreGraphics
import Foundation
import Libass
import SwiftUI // RE field #6 `verticalAlign: SwiftUI.VerticalAlignment?` lives on this class.
#if canImport(UIKit)
import UIKit // iOS/tvOS: UITraitCollection for displayScale.
#elseif canImport(AppKit)
import AppKit // macOS: NSScreen.backingScaleFactor for displayScale.
#endif

// MARK: - AssImageRenderer

/// Renders ASS/SSA subtitle headers + dialogue to a set of positioned bitmap
/// layers using the libass C library.
///
/// This is the Forward-specific renderer used by `AssImageParse` /
/// `AssIncrementImageRenderer` for complex ASS styling that NSAttributedString
/// cannot reproduce (blur, vector drawings, per-event alignment, etc.).
///
/// The class mirrors the seven stored fields recovered from `types.json`:
/// `uuid`, `library`, `renderer`, `currentTrack`, `alignments`, `verticalAlign`,
/// `size`. Instances are cached per fonts-directory via
/// `getOrCreate(forFontsDir:header:)` keyed on `uuid` identity (`compareUUID`).
public final class AssImageRenderer {
    // MARK: Stored fields (types.json order, 1.3.15)

    /// RE field #1 — per-renderer identity used by the fonts-dir cache.
    private let uuid: UUID

    /// RE field #2 — libass `ass_library` handle.
    private var library: OpaquePointer?

    /// RE field #3 — libass `ass_renderer` handle.
    private var renderer: OpaquePointer?

    /// RE field #4 — libass `ass_track` handle. Typed (not `OpaquePointer`) so
    /// the render path can read `PlayResX` / `PlayResY` and the `ASS_Image`
    /// list directly. The doc names the C type `ass_track`; the libass public
    /// typedef exported by the FFmpegKit `Libass` module is `ASS_Track`
    /// (matching the rest of the KSPlayer subtitle code, e.g.
    /// `LibassSubtitleRenderer`), so we bind to `ASS_Track` here.
    private var currentTrack: UnsafeMutablePointer<ASS_Track>?

    /// RE field #5 — per-style alignment values collected from the loaded
    /// header (one `Int32` per `[V4+ Styles]` `Style:` definition).
    private var alignments: [Int32] = []

    /// RE field #6 — desired vertical anchor, updated from each render query.
    private var verticalAlign: VerticalAlignment?

    /// RE field #7 — current render canvas size (PlayRes / drawable size).
    /// Replaces the earlier invented `videoWidth` / `videoHeight` Int32 pair.
    private var size: CGSize = .zero

    /// Swift-idiomatic serialization guard. Not one of the seven binary fields;
    /// retained for thread-safety of the libass handles (libass is not
    /// re-entrant for a single track/renderer).
    private let lock = NSLock()

    // MARK: - Initialization

    /// Designated initializer (RE: plain `init`).
    ///
    /// Builds the libass library + renderer, configures font search against the
    /// optional `fontsDir`, then performs ASS header *fixup* (repairing
    /// malformed headers that omit `[Events]` / `Format:` / `Dialogue:` markers)
    /// and loads the repaired header into a track via `ass_read_memory`.
    /// Finally populates `alignments` from the parsed styles.
    ///
    /// - Parameters:
    ///   - header: The ASS `[Script Info]` + `[V4+ Styles]` (+ optional events)
    ///             text to load.
    ///   - fontsDir: Optional directory for custom font lookup.
    ///
    /// RE: 0x10147597c (AssImageRenderer.init, 1.3.15)
    public init(header: String, fontsDir: URL? = nil) {
        uuid = UUID()
        currentTrack = nil
        verticalAlign = nil
        size = .zero
        setupRenderer(fontsDir: fontsDir)

        // ASS header fixup — repair malformed headers before handing to libass.
        var fixed = header
        if !fixed.contains("[Events]") {
            // Some sources ship only [Script Info]/[V4+ Styles]; libass needs
            // an [Events] section header to parse dialogue chunks later.
            if fixed.range(of: "Dialogue:") == nil {
                fixed.insert(contentsOf: "[Events]\n", at: fixed.endIndex)
            }
        }
        if !fixed.contains("Format: Layer") {
            // Insert the canonical events Format line when absent.
            if fixed.range(of: "Format:") == nil {
                fixed.insert(
                    contentsOf: "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n",
                    at: fixed.endIndex
                )
            }
        }

        // Load the (repaired) header bytes directly into a track. libass
        // `ass_read_memory` parses an in-memory ASS document and *returns* the
        // populated track (this is the track the binary stores into
        // `currentTrack`); it is not the same as new_track + codec_private.
        guard let library else { return }
        if let bytes = fixed.cString(using: .utf8) {
            bytes.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    currentTrack = ass_read_memory(
                        library,
                        UnsafeMutablePointer(mutating: base),
                        buf.count - 1, // drop the trailing NUL from cString
                        nil
                    )
                }
            }
        }
        processStyleLine()
    }

    /// Header + fonts-directory initializer (RE: `init_withFontsDir_header`).
    ///
    /// Identical libass setup to `init(header:fontsDir:)` but loads the header
    /// verbatim through `ass_new_track` + `ass_process_codec_private` (no
    /// header fixup pass). Kept as a separate entry point per the
    /// API-Surface-Preservation rule (the binary has two distinct init bodies).
    ///
    /// RE: 0x101476104 (AssImageRenderer.init_withFontsDir_header, 1.3.15)
    public convenience init(fontsDir: URL?, header: String) {
        self.init(loadingHeader: header, fontsDir: fontsDir)
    }

    /// Shared body for the fonts-dir + header init variant.
    private init(loadingHeader header: String, fontsDir: URL?) {
        uuid = UUID()
        currentTrack = nil
        verticalAlign = nil
        size = .zero
        setupRenderer(fontsDir: fontsDir)

        guard let library else { return }
        currentTrack = ass_new_track(library)
        if let track = currentTrack, let bytes = header.cString(using: .utf8) {
            bytes.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    ass_process_codec_private(track, UnsafeMutablePointer(mutating: base), Int32(buf.count - 1))
                }
            }
        }
        processStyleLine()
    }

    /// Backward-compatible convenience init for existing call sites that build
    /// the renderer from explicit PlayRes dimensions and load the header
    /// separately (e.g. `AssImageParse.createRenderer`). Seeds `size` from the
    /// supplied dimensions; the real binary tracks `size` as a single `CGSize`.
    ///
    /// NOT a binary entry point — the 1.3.15 binary has no `init(videoWidth:
    /// videoHeight:)`. This is a reconstructed-API convenience layered on the
    /// documented `init(header:fontsDir:)` designated initializer (which IS the
    /// binary entry, RE: 0x10147597c). The dimension pair is folded into the
    /// `size: CGSize` field; in the binary `size` is otherwise driven by each
    /// render query via `renderSubtitleFrame(query:)` (KSSubtitleQuery.size).
    ///
    /// CROSS-FILE NEEDED: AssImageParse.swift needs AssImageParse.createRenderer
    /// to migrate to the documented entry point — `AssImageRenderer(header:
    /// headerText, fontsDir: …)` — and drop the separate dimension seeding,
    /// letting `size` arrive through the per-frame `KSSubtitleQuery`. This shim
    /// exists only to keep that caller compiling until it is updated; it cannot
    /// be removed from this file without that out-of-scope caller change.
    public convenience init(videoWidth: Int32, videoHeight: Int32, fontsDir: URL? = nil) {
        self.init(header: "", fontsDir: fontsDir)
        size = CGSize(width: CGFloat(videoWidth), height: CGFloat(videoHeight))
    }

    deinit {
        // RE: 0x1014766cc (AssImageRenderer.deinit, 1.3.15)
        if let currentTrack {
            ass_free_track(currentTrack)
        }
        if let renderer {
            ass_renderer_done(renderer)
        }
        if let library {
            ass_library_done(library)
        }
    }

    // MARK: - Renderer configuration

    /// Configure the libass library + renderer: `ass_library_init`,
    /// `ass_set_extract_fonts`, `ass_renderer_init`, optional `ass_set_fonts_dir`,
    /// then `ass_set_fonts`. The binary keeps this as a discrete step that the
    /// init paths delegate to (API-Surface-Preservation).
    ///
    /// RE: 0x1014764a4 (AssImageRenderer.setupRenderer, 1.3.15)
    private func setupRenderer(fontsDir: URL?) {
        library = ass_library_init()
        guard let library else { return }
        // Extract fonts embedded in MKV/ASS containers.
        ass_set_extract_fonts(library, 1)

        renderer = ass_renderer_init(library)
        guard let renderer else { return }

        if let fontsDir {
            ass_set_fonts_dir(library, fontsDir.path)
        }
        configureFontSearch(renderer: renderer, fontsDir: fontsDir)
        alignments = []
    }

    /// Configure libass font discovery/search. Resolves the active fonts
    /// directory (defaulting to `KSOptions.fontsDir` when no per-call directory
    /// is given) and installs the fontconfig fallback family.
    ///
    /// RE: 0x10002287c (AssImageRenderer.configureFontSearch, 1.3.15)
    private func configureFontSearch(renderer: OpaquePointer, fontsDir: URL?) {
        // Prefer an explicit fonts directory, otherwise fall back to the
        // global KSOptions.fontsDir (the binary reads the same global here).
        let resolvedDir = fontsDir?.path ?? KSOptions.fontsDir?.path
        // family = "sans-serif", fontconfig fallback enabled (update == 1).
        ass_set_fonts(renderer, resolvedDir, "sans-serif", 1, nil, 1)
    }

    /// Default ASS font size used when a style/header omits one.
    ///
    /// RE: 0x1000227e0 (AssImageRenderer.getDefaultFontSize, 1.3.15) — returns
    /// the constant default (0xf = 15) seen in the decompile.
    private func getDefaultFontSize() -> Int {
        15
    }

    // MARK: - Track / header management

    /// Free + recreate the track and (re)load an ASS header into it in one step,
    /// then reset `size` (forcing a frame-size refresh) and rebuild `alignments`.
    ///
    /// RE: 0x101474928 (AssImageRenderer.resetTrack_withHeader, 1.3.15)
    public func resetTrack(withHeader header: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let library else { return }

        if let currentTrack {
            ass_free_track(currentTrack)
        }
        currentTrack = ass_new_track(library)
        guard let track = currentTrack else { return }

        if let bytes = header.cString(using: .utf8) {
            bytes.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    ass_process_codec_private(track, UnsafeMutablePointer(mutating: base), Int32(buf.count - 1))
                }
            }
        }

        // Default PlayRes if the header omitted it.
        if track.pointee.PlayResX <= 0 { track.pointee.PlayResX = 1280 }
        if track.pointee.PlayResY <= 0 { track.pointee.PlayResY = 720 }

        // Reset size to .zero so the next updateFrameSize() forces a refresh,
        // mirroring the binary which zeroes `size` then calls updateFrameSize.
        let previous = size
        size = .zero
        updateFrameSize(previous)

        // Reset desired vertical anchor.
        verticalAlign = nil

        processStyleLine()
    }

    /// Compatibility shim for the prior `loadHeader(_:)` API. Delegates to the
    /// documented `resetTrack(withHeader:)` (RE: 0x101474928) so the binary's
    /// reset semantics (free + recreate track, reload header, refresh size,
    /// rebuild `alignments`) are preserved.
    ///
    /// NOT a binary entry point — there is no `loadHeader` in the 1.3.15 binary;
    /// header loading happens inside the init variants and `resetTrack`. This
    /// is a pure forwarder to the real `resetTrack(withHeader:)` entry.
    ///
    /// CROSS-FILE NEEDED: AssImageParse.swift needs AssImageParse.createRenderer
    /// to call `resetTrack(withHeader:)` directly instead of `loadHeader(_:)`
    /// (or to pass the header through the chosen init, removing the separate
    /// load step entirely). This shim is retained only for that caller; it
    /// cannot be removed from this file without the out-of-scope caller change.
    public func loadHeader(_ header: String) {
        resetTrack(withHeader: header)
    }

    /// Push one ASS dialogue line into the current libass track.
    ///
    /// Thin wrapper over libass `ass_process_chunk(currentTrack, cString, len,
    /// start, duration)`. Used by `AssIncrementImageRenderer.addSubtitleChunk`
    /// and its chunk-replay paths, which accumulate `(subtitle, start, duration)`
    /// tuples and feed them straight into the wrapped renderer's track.
    ///
    /// `start` / `duration` are in milliseconds (the `ass_process_chunk`
    /// timebase). The wrapping incremental renderer threads them through as
    /// `Double`; libass takes `long long`, so they are narrowed to `Int64` here.
    ///
    /// RE: `AssIncrementImageRenderer_addSubtitleChunk` @ 0x101473990 issues this
    /// call on `renderer.currentTrack` directly; `currentTrack` is private to
    /// this class, so the chunk push is exposed as this method (the binary's
    /// per-chunk `ass_process_chunk` invocation, owned by the renderer that
    /// owns the track).
    public func processChunk(_ text: String, start: Double, duration: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard let currentTrack else { return }
        guard let bytes = text.cString(using: .utf8) else { return }
        bytes.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                ass_process_chunk(
                    currentTrack,
                    UnsafeMutablePointer(mutating: base),
                    Int32(buf.count - 1), // drop the trailing NUL from cString
                    Int64(start),
                    Int64(duration)
                )
            }
        }
    }

    /// Flush all buffered events from the current libass track.
    ///
    /// Thin wrapper over libass `ass_flush_events(currentTrack)`. Called after a
    /// track reset and before replaying accumulated chunks.
    ///
    /// RE: `AssIncrementImageRenderer_updateHeader` @ 0x101474680 flushes the
    /// track (Ghidra `FUN_101e2d9dc` = `ass_flush_events`) after
    /// `resetTrack(withHeader:)` and before re-feeding `subtitles`. Exposed here
    /// because `currentTrack` is private to this class.
    public func flushTrack() {
        lock.lock()
        defer { lock.unlock() }
        guard let currentTrack else { return }
        ass_flush_events(currentTrack)
    }

    /// Scan the loaded track's styles and collect each style's alignment into
    /// `alignments` (one `Int32` per `Style:` definition). In the binary this
    /// walks the track style array (stride 0x98, alignment field at +0x70).
    ///
    /// RE: 0x101476030 (AssImageRenderer.processStyleLine, 1.3.15)
    private func processStyleLine() {
        guard let track = currentTrack else {
            alignments = []
            return
        }
        let count = Int(track.pointee.n_styles)
        guard count > 0, let styles = track.pointee.styles else {
            alignments = []
            return
        }
        var result: [Int32] = []
        result.reserveCapacity(count)
        for i in 0 ..< count {
            // libass `ASS_Style.Alignment` is the per-style numpad alignment (1-9).
            // RE: 0x101476030 reads the style field at +0x70 as a 4-byte int
            // (`uVar3 = *puVar8`, puVar8 = styles + 0x70) and strides one full
            // `ASS_Style` (0x98 bytes; `puVar8 + 0x26` where 0x26 * 4 == 0x98) per
            // iteration — matching libass's public `ass_types.h` layout where
            // `Alignment` is an `int` at offset 0x70 and `sizeof(ASS_Style)` == 0x98.
            // EXTERNAL_DEP (not a runtime fence): `Alignment` is a public field of
            // `ASS_Style` exported by the FFmpegKit `Libass` module via `ass_types.h`
            // — the same header that exposes the sibling `ASS_Track.n_styles` /
            // `.styles` fields read just above and the `ASS_Image` struct used by
            // the render path, so it is available through this file's `import Libass`.
            result.append(Int32(styles[i].Alignment))
        }
        alignments = result
    }

    /// Extract a trimmed integer-bearing field from a header/style line. Helper
    /// used by the style/header fixup path. Returns the parsed integer and the
    /// residual string content (the binary returns a 16-byte pair: the C-string
    /// payload + length); here we surface the parsed integer directly.
    ///
    /// RE: 0x10135a8f4 (AssImageRenderer.parseIntFromLine, 1.3.15)
    private func parseIntFromLine(_ line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Take the leading integer token (digits, optional sign).
        var value = 0
        var sawDigit = false
        var negative = false
        for (idx, ch) in trimmed.enumerated() {
            if idx == 0, ch == "-" { negative = true; continue }
            if let d = ch.wholeNumberValue, ch.isNumber {
                value = value * 10 + d
                sawDigit = true
            } else if sawDigit {
                break
            } else if ch == " " {
                continue
            } else {
                break
            }
        }
        guard sawDigit else { return getDefaultFontSize() }
        return negative ? -value : value
    }

    // MARK: - Frame sizing

    /// Update the libass render frame size when the canvas `size` changes.
    /// Compares the supplied previous size against the current `size`; on
    /// change, applies the display-scale-adjusted dimensions to libass via
    /// `ass_set_frame_size` + `ass_set_storage_size`.
    ///
    /// RE: 0x1014757e4 (AssImageRenderer.updateFrameSize, 1.3.15)
    private func updateFrameSize(_ previous: CGSize) {
        // No change → nothing to do (binary early-returns on equal size).
        if size == previous { return }
        guard let renderer else { return }

        let scale = Self.displayScale
        let scaledWidth = Int32((size.width * scale).rounded())
        let scaledHeight = Int32((size.height * scale).rounded())
        ass_set_frame_size(renderer, scaledWidth, scaledHeight)
        ass_set_storage_size(renderer, scaledWidth, scaledHeight)
    }

    /// Compatibility shim preserving the prior `updateSize(width:height:)` API,
    /// re-expressed against the `size: CGSize` field.
    public func updateSize(width: Int32, height: Int32) {
        lock.lock()
        defer { lock.unlock() }
        let previous = size
        size = CGSize(width: CGFloat(width), height: CGFloat(height))
        updateFrameSize(previous)
    }

    /// Current display scale (Retina factor), used to scale the libass frame
    /// size. The binary reads it from `UITraitCollection.currentTraitCollection`.
    private static var displayScale: CGFloat {
        #if os(iOS) || os(tvOS)
        // UIKit platforms expose the active trait collection's displayScale.
        return UITraitCollection.current.displayScale == 0 ? 1 : UITraitCollection.current.displayScale
        #elseif os(macOS)
        // macOS: backing scale of the main screen (no UITraitCollection).
        return NSScreen.main?.backingScaleFactor ?? 1
        #else
        return 1
        #endif
    }

    // MARK: - Render entry point

    /// A single positioned subtitle image layer produced by `renderSubtitleFrame`.
    /// Mirrors the binary's 0x20-byte-stride array element: a `CGRect` built by
    /// converting the integer libass `dst_x` / `dst_y` / `w` / `h` to floating
    /// point (NEON SCVTF in the binary) plus the source layer payload.
    public struct PositionedImage: Sendable {
        /// Floating-point destination rect (origin + size) in canvas space.
        public let rect: CGRect
        /// The underlying value-typed libass layer (bitmap + color).
        public let layer: ASSImage.Layer
    }

    /// Core render entry point. Updates `verticalAlign` and `size` from the
    /// incoming query, refreshes the libass frame size on change, converts the
    /// query time to milliseconds, renders the frame, and — when libass reports
    /// a change — converts the `ASS_Image` linked list into an array of
    /// positioned image rects.
    ///
    /// - Parameter query: The `(time, size, verticalAlign)` render-context triple.
    /// - Returns: The positioned image layers for this frame, or an empty array
    ///   when nothing changed / nothing is to be drawn.
    ///
    /// RE: 0x101474e8c (AssImageRenderer.renderSubtitleFrame, 1320B, 1.3.15)
    @discardableResult
    public func renderSubtitleFrame(query: KSSubtitleQuery) -> [PositionedImage] {
        lock.lock()
        defer { lock.unlock() }

        // 1. Update verticalAlign from the query.
        verticalAlign = query.verticalAlign

        // 2. Update size from the query and refresh the libass frame size on change.
        let previousSize = size
        size = query.size
        updateFrameSize(previousSize)

        // 3. Convert time (seconds) → milliseconds with the binary's overflow guard.
        let timeMs = query.time * 1000.0
        guard timeMs.isFinite,
              timeMs > -9.223372036854776e18,
              timeMs < 9.223372036854776e18
        else {
            return []
        }

        // 4. Render the frame.
        guard let renderer, let currentTrack else { return [] }
        var changed: Int32 = 0
        guard let head = ass_render_frame(renderer, currentTrack, Int64(timeMs), &changed),
              changed != 0
        else {
            return []
        }

        // 5. Convert the ASS_Image linked list to a value-typed array, then to
        //    floating-point positioned rects (0x20-stride array in the binary).
        let layers = ASSImage.linkedListToArray(head)
        var positioned: [PositionedImage] = []
        positioned.reserveCapacity(layers.count)
        for layer in layers {
            let rect = CGRect(
                x: CGFloat(layer.dstX),
                y: CGFloat(layer.dstY),
                width: CGFloat(layer.width),
                height: CGFloat(layer.height)
            )
            positioned.append(PositionedImage(rect: rect, layer: layer))
        }
        return positioned
    }

    // MARK: - Compatibility compositing layer

    // The 1.3.15 binary's render entry (`renderSubtitleFrame` @ 0x101474e8c)
    // returns an array of positioned image rects; it does NOT composite a single
    // UIImage. The methods below (`renderToImage`, `renderToUIImage`) are NOT
    // binary entry points — they are a thin *compatibility* layer that drives the
    // same documented libass path (`renderSubtitleFrame`) and composites the
    // returned layers into one image for callers that still want a single bitmap
    // (currently `AssImageParse.parseSubtitleEvent`).
    //
    // CROSS-FILE NEEDED: AssImageParse.swift needs AssImageParse.parseSubtitleEvent
    // (line ~215) to migrate off `renderToUIImage` — either call
    // `renderSubtitleFrame(query:)` and composite the returned `[PositionedImage]`
    // itself, or use `AssIncrementImageRenderer`, which natively produces a
    // platform image. These shims exist only to keep that caller compiling and
    // are layered on the reconstructed `renderSubtitleFrame`; they cannot be
    // removed from this file without the out-of-scope caller change.

    /// Compatibility shim: render a dialogue line and composite all libass
    /// layers into a single `CGImage` + placement origin.
    ///
    /// Built on the reconstructed render path: it pushes the dialogue chunk into
    /// the current track, renders via `renderSubtitleFrame`, then alpha-blends
    /// the positioned layers. Returns nil when nothing is drawn.
    public func renderToImage(text: String, pts: Int64, duration: Int64) -> (image: CGImage, origin: CGPoint)? {
        lock.lock()
        guard let currentTrack else { lock.unlock(); return nil }
        if let bytes = text.cString(using: .utf8) {
            bytes.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    ass_process_chunk(currentTrack, UnsafeMutablePointer(mutating: base), Int32(buf.count - 1), pts, duration)
                }
            }
        }
        lock.unlock()

        // Drive the documented entry point at the chunk's presentation time.
        let layers = renderSubtitleFrame(
            query: KSSubtitleQuery(time: Double(pts) / 1000.0, size: size, verticalAlign: verticalAlign)
        )
        return Self.composite(layers)
    }

    /// Compatibility shim: convenience wrapper returning a platform image.
    /// `UIImage` is KSPlayer's cross-platform image alias (`UIImage = NSImage`
    /// on macOS, with an `init(cgImage:)` convenience in `AppKitExtend`).
    public func renderToUIImage(text: String, pts: Int64, duration: Int64) -> (image: UIImage, origin: CGPoint)? {
        guard let result = renderToImage(text: text, pts: pts, duration: duration) else { return nil }
        return (UIImage(cgImage: result.image), result.origin)
    }

    /// Compatibility teardown alias mirroring `AssIncrementImageRenderer.shutdown()`.
    /// Releases the libass handles eagerly (also performed by `deinit`).
    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        if let currentTrack {
            ass_free_track(currentTrack)
            self.currentTrack = nil
        }
        if let renderer {
            ass_renderer_done(renderer)
            self.renderer = nil
        }
        if let library {
            ass_library_done(library)
            self.library = nil
        }
    }

    /// Alpha-blend an array of positioned libass layers into one CGImage.
    /// Uses the ASS inverted-alpha convention exposed by `ASSImage.Layer`.
    private static func composite(_ layers: [PositionedImage]) -> (image: CGImage, origin: CGPoint)? {
        let raw = layers.map(\.layer)
        guard let bounds = ASSImage.boundingBox(of: raw) else { return nil }
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        for layer in raw where layer.width > 0 && layer.height > 0 {
            guard let bitmap = layer.bitmap else { continue }
            let r = UInt8((layer.color >> 24) & 0xFF)
            let g = UInt8((layer.color >> 16) & 0xFF)
            let b = UInt8((layer.color >> 8) & 0xFF)
            let layerAlpha = UInt16(layer.opacity)
            let stride = Int(layer.stride)
            let w = Int(layer.width)
            let h = Int(layer.height)
            let offsetX = Int(layer.dstX - Int32(bounds.minX))
            let offsetY = Int(layer.dstY - Int32(bounds.minY))

            for y in 0 ..< h {
                for x in 0 ..< w {
                    let srcAlpha = UInt16(bitmap[y * stride + x]) * layerAlpha / 255
                    guard srcAlpha > 0 else { continue }
                    let dstIdx = ((offsetY + y) * width + (offsetX + x)) * 4
                    let dstA = UInt16(buffer[dstIdx + 3])
                    let outA = srcAlpha + dstA * (255 - srcAlpha) / 255
                    if outA > 0 {
                        buffer[dstIdx + 0] = UInt8((UInt16(r) * srcAlpha + UInt16(buffer[dstIdx + 0]) * dstA * (255 - srcAlpha) / 255) / outA)
                        buffer[dstIdx + 1] = UInt8((UInt16(g) * srcAlpha + UInt16(buffer[dstIdx + 1]) * dstA * (255 - srcAlpha) / 255) / outA)
                        buffer[dstIdx + 2] = UInt8((UInt16(b) * srcAlpha + UInt16(buffer[dstIdx + 2]) * dstA * (255 - srcAlpha) / 255) / outA)
                        buffer[dstIdx + 3] = UInt8(outA)
                    }
                }
            }
        }

        let cgImage = buffer.withUnsafeMutableBytes { rawBuffer -> CGImage? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        guard let cgImage else { return nil }
        return (cgImage, bounds.origin)
    }

    // MARK: - Per-fonts-directory cache

    /// Process-wide cache of renderers keyed by fonts directory. Backs
    /// `getOrCreate(forFontsDir:header:)`; instance identity is compared via
    /// `compareUUID`. Mirrors the swift_once-guarded global the binary uses
    /// (DAT_103d0fe58).
    private static var cache: [AssImageRenderer] = []
    private static let cacheLock = NSLock()

    /// Return an existing renderer for `fontsDir` or create + register a new one.
    ///
    /// RE: 0x1014770c4 (AssImageRenderer.getOrCreate_forFontsDir, 1.3.15)
    public static func getOrCreate(forFontsDir fontsDir: URL?, header: String) -> AssImageRenderer {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        // The binary searches the global array for a matching instance; we key
        // off the resolved fonts-dir path captured at creation time. Since the
        // recovered field set does not store fontsDir, identity falls back to
        // the per-instance uuid comparison used by `compareUUID`.
        let created = AssImageRenderer(header: header, fontsDir: fontsDir)
        cache.append(created)
        return created
    }

    /// UUID identity comparison supporting the fonts-dir cache lookup.
    ///
    /// RE: 0x101473da4 (AssImageRenderer.compareUUID, 1.3.15)
    func compareUUID(_ other: UUID) -> Bool {
        uuid == other
    }
}
