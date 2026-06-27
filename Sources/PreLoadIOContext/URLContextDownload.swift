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
//   init   — real designated init s3 @101b90bc0 → SHARED inner FUN_101b90c58 (cached;
//            7-arg, also reused by CacheIOContext/ReadCacheIOContext to build their
//            `download`). Opens an FFmpeg URLContext (deep IO; stripped calls named
//            only by the P2 oracle) → UNRESOLVED→P2; inherited init(bufferSize:) is
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
    var keepAlive: Bool = false
    // isReadComplete: whether the download has reached completion. v4 concrete.
    var isReadComplete: Bool = false
    // url: the source URL of the download. Inner init copies it via Foundation::URL
    //   type-metadata + value-witness (dispositive → URL, not String).
    var url: URL? // type URL; optionality inferred — ⚑

    // UNRESOLVED: real designated init s3 @101b90bc0 → SHARED inner FUN_101b90c58 (7 args; also reused by
    //   CacheIOContext/ReadCacheIOContext to build their `download`). Opens an FFmpeg URLContext
    //   (multiple_requests option, avio open) — deep FFmpeg IO whose stripped calls only the P2 oracle names.
    //   Not reconstructed; inherited init(bufferSize:) is the compilable spine. — P2
    public override init(bufferSize: Int32 = 32 * 1024) {
        super.init(bufferSize: bufferSize)
    }

    // UNRESOLVED: read(buffer:size:) / write(buffer:size:) / seek(offset:whence:)
    //   overrides are devirtualized in the binary (no readable body) — inherited
    //   from AbstractAVIOContext, NOT reconstructed. — P2
}
