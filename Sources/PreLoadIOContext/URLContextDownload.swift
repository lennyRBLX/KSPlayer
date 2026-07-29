import Foundation
import KSPlayer
import FFmpegKit   // URLContext (FFmpeg private libavformat type) is declared in FFmpegKit's avformat_shim.h
import Libavformat

// URLContextDownload — an AbstractAVIOContext that downloads through an FFmpeg
// URLContext (libavformat protocol handler), used to populate the cache.
//
// Reconstructed A+ structure-faithful from the Forward 1.3.17 binary:
//   fields — __swift5_fieldmd reflection (NAMES + ORDER + COUNT authoritative);
//            `context`/`keepAlive`/`isReadComplete` are v4 concrete (transcribed
//            verbatim); `url` is ⚑ best-effort (confirmed via l2_field_gate).
//   init   — real designated init s3 @101b90bc0 → SHARED inner FUN_101b90c58 (cached;  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
//            7-arg, also reused by CacheIOContext/ReadCacheIOContext to build their
//            `download`). Opens an FFmpeg URLContext (deep IO; stripped calls named
//            only by the P2 oracle) → UNRESOLVED→P8 (IO-completion); inherited init(bufferSize:) is
//            the compilable spine.
//
// UNRESOLVED: AbstractAVIOContext overrides (read/write/seek) are devirtualized in
//   the binary (no readable body) → inherited, NOT reconstructed. — P2
//
// URLContext is FFmpeg's libavformat *private* type — declared in FFmpegKit's
//   avformat_shim.h, so it resolves via `import FFmpegKit` (added to this target's
//   dependencies in Package.swift). PreLoadIOContext builds green via
//   `swift build --target PreLoadIOContext`. NOTE: the KSPlayer xcodebuild scheme
//   (validate_build.sh ios) does NOT compile PreLoadIOContext → verify this module
//   with `swift build`.
public class URLContextDownload: AbstractAVIOContext {
    // --- stored fields (binary __swift5_fieldmd order) ---
    // context: the FFmpeg URLContext driving the download. v4 concrete.
    var context: UnsafeMutablePointer<URLContext>?
    // keepAlive: whether the connection is kept open after a read. v4 concrete.
    let keepAlive: Bool = false
    // isReadComplete: whether the download has reached completion. v4 concrete.
    let isReadComplete: Bool = false
    // url: the source URL of the download. Inner init copies it via Foundation::URL
    //   type-metadata + value-witness (dispositive → URL, not String).
    // ⚑[tool=binding_gate ref=URLContextDownload:__swift5_fieldmd result=pinned — binary says `let`, source cannot be]
    //   Session 61 binding sweep: these fields' FieldRecord flags word is 0x00000000
    //   (= `let`), but the Swift compiler REFUSES that spelling here. Left as `var`.
    //   • url — assigned after super.init(); a `let` must be set before it
    //   Real divergence, not fixable by a keyword flip. Detail + the full 33:
    //   reconstruction/binding_refuted_s61.json
    var url: URL? // type URL; optionality inferred — ⚑

    // UNRESOLVED: real designated init s3 @101b90bc0 → SHARED inner FUN_101b90c58 (7 args; also reused by  ⚑[tool=resolve_fun_pins ref=FUN_101b90c58:0x101b90c58 result=RESOLVES_UNIQUELY] = PreLoadIOContext.URLContextDownload.init(url: Foundation.URL, flags: Swift.Int32, options: Swift.UnsafeMutablePointer<Swift.OpaquePointer?>?, interrupt: __C.AVIOInterruptCB, isReadComplete: Swift.Bool) throws -> PreLoadIOContext.URLContextDownload
    //   CacheIOContext/ReadCacheIOContext to build their `download`). Opens an FFmpeg URLContext
    //   (multiple_requests option, avio open) — deep FFmpeg IO whose stripped calls only the P2 oracle names.
    //   Not reconstructed; inherited init(bufferSize:) is the compilable spine. — P2
    public override init(bufferSize: Int32 = 32 * 1024) {
        super.init(bufferSize: bufferSize)
    }

    // urlContext (base slot +0xa8) — io_open's terminal URLContext accessor.
    //   URLContextDownload is the download-chain TERMINAL: it exposes its own FFmpeg
    //   URLContext (the `context` field @+0x18) directly. The decompile is a checked-
    //   exclusivity read of self.context (beginAccess then the load) — the beginAccess is
    //   compiler-emitted instrumentation, invisible at source; the body is `{ context }`.
    // ⚑[tool=prefetch_decompiles ref=FUN_10081cbbc:0x10081cbbc result=_swift_beginAccess(self+0x18);return*(self+0x18) == self.context]
    public override var urlContext: UnsafeMutablePointer<URLContext>? { context }

    // UNRESOLVED: read(buffer:size:) / write(buffer:size:) / seek(offset:whence:)
    //   overrides are devirtualized in the binary (no readable body) — inherited
    //   from AbstractAVIOContext, NOT reconstructed. — P2
}
