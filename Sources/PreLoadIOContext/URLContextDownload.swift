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
//   init   — s3 @101b90bc0: the cached decompile is the outer *allocating* thunk
//            (_swift_allocObject → FUN_101b90c58(7 args) → return); the inner
//            field-store body (FUN_101b90c58) is NOT in the cached decompile set
//            → init is a faithful spine + UNRESOLVED for the field assignments.
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
    var keepAlive: Bool = false
    // isReadComplete: whether the download has reached completion. v4 concrete.
    var isReadComplete: Bool = false
    // url: the source URL string of the download.
    var url: String? // type inferred — ⚑ (String vs URL not resolvable from s3 thunk; confirm via l2)

    // s3 @101b90bc0 — designated init (7 inner args in the thunk).
    //   Outer thunk: _swift_allocObject → FUN_101b90c58(param_1..param_7) → return.
    // UNRESOLVED: inner init FUN_101b90c58 (field-store sequence + the exact param
    //   set / decomposition — a String is 2 words, param_7 is a 1-byte Bool) is
    //   NOT in the cached decompiles — faithful spine only. super.init() with
    //   AbstractAVIOContext's default bufferSize.
    public override init(bufferSize: Int32 = 32 * 1024) {
        super.init(bufferSize: bufferSize)
    }

    // UNRESOLVED: read(buffer:size:) / write(buffer:size:) / seek(offset:whence:)
    //   overrides are devirtualized in the binary (no readable body) — inherited
    //   from AbstractAVIOContext, NOT reconstructed. — P2
}
