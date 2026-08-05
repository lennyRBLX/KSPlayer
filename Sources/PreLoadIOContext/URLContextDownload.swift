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
    // ⚑ s105: renamed with the base — see AbstractAVIOContext.nextAVOptions. Body 0x100822e00
    // is a 1-instruction `b 0x10081cbbc`, and that target is a plain `return *(self+0x18)`, i.e.
    // this class's first field `context`. The raw-pointer conversion is a no-op bitcast.
    public override func nextAVOptions() -> UnsafeMutableRawPointer? { context.map { UnsafeMutableRawPointer($0) } }

    /// @0x101b91150, 18 instructions. Trie: `URLContextDownload.fileSize() -> Swift.Int64`;
    /// `override_table.py --impl 0x101b91150` answers YES at index 2, so it overrides
    /// `AbstractAVIOContext.fileSize()`.
    ///
    ///   · a READ `swift_beginAccess` (flags 0, 0) on self+0x18 then `ldr x0,[x20,#0x18]` — this
    ///     class's `context`, the field `nextAVOptions` above already pins at that offset.
    ///   · `cbz x0` returns the immediate −1, which is exactly the base class's default body.
    ///   · otherwise `x1 = 0`, `w2 = 0x10000` and one call. 0x10000 is `AVSEEK_SIZE`
    ///     (avio.h:468 in this build), so the shape is (URLContext, pos 0, AVSEEK_SIZE) → Int64.
    /// ⚑ The callee is NAMED FROM THIS BUILD'S HEADERS, not from the address: `ffmpeg_name_oracle`
    ///   cannot narrow 0x1030c07ac (59 band candidates, and `ffurl_seek` is not among them), which
    ///   is the expected `ffurl_*` negative. libavformat/url.h in FFmpeg-n8.1.1 shows why —
    ///   `ffurl_seek` is a `static inline` wrapper that does nothing but
    ///   `return ffurl_seek2(h, pos, whence)`, so it cannot survive as a call target at all; the
    ///   exported function is `ffurl_seek2(void *urlcontext, int64_t pos, int whence)`. That name
    ///   is independently corroborated inside the binary: the log literal this reconstruction
    ///   already reads at LimitSeparatePreLoadIOContext carries the text "more ffurl_seek2 ".
    /// ⚑[tool=override_table ref=URLContextDownload.fileSize:0x101b91150 result=YES-index-2]
    /// ⚑[tool=ffmpeg_name_oracle ref=ffurl_seek2:0x1030c07ac result=NOT-UNIQUELY-NAMED-59-candidates]
    /// ⚑[tool=export_trie_oracle ref=URLContextDownload.fileSize:0x101b91150 result=LOCATED]
    ///
    /// ⚑ s109: NOW DECLARED. The blocker was never the read — it was that `ffurl_seek2` was not
    /// in scope, because the built Libavformat.framework exports only
    /// avformat/avio/config/os_support/version and url.h is internal. FFmpegKit's
    /// `avformat_shim.h` is where this reconstruction already restates internal libavformat
    /// prototypes (`ff_isom_write_vpcc` sits there for exactly the same reason, with its own
    /// header import commented out), and it already declares `URLContext` and
    /// `ffurl_context_class` for this very file. The prototype was added there verbatim from
    /// url.h:207 — `void *` for the context, not `URLContext *`.
    override public func fileSize() -> Int64 {
        guard let context else {
            return -1
        }
        return ffurl_seek2(context, 0, AVSEEK_SIZE)
    }

    /// @0x101b910f0, 24 instructions. `override_table.py --impl` answers YES at index 1.
    /// Identical to `fileSize()` above except that the two immediates are replaced by the
    /// parameters: `x1 = x21` is `offset` and `x2 = x19` is `whence`, both moved out of x0/x1 in
    /// the prologue before the `context` read. Same `cbz` → −1 guard.
    /// ⚑[tool=override_table ref=URLContextDownload.seek(offset:whence:):0x101b910f0 result=YES-index-1]
    override public func seek(offset: Int64, whence: Int32) -> Int64 {
        guard let context else {
            return -1
        }
        return ffurl_seek2(context, offset, whence)
    }

    // ⚠️ s109 CORRECTION: this note used to include `seek(offset:whence:)` in the
    //   "devirtualized in the binary (no readable body)" list. That was wrong — the trie names
    //   `URLContextDownload.seek(offset:whence:)` at 0x101b910f0 and its 24-instruction body is
    //   read and declared above. `read(buffer:size:)` and `write(buffer:size:)` are unaffected by
    //   this correction and remain unlisted in the trie for this class.
    // UNRESOLVED: read(buffer:size:) / write(buffer:size:) overrides are devirtualized in the
    //   binary (no readable body) — inherited from AbstractAVIOContext, NOT reconstructed. — P2
}
