import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via LimitPreLoadIOContext → … → CacheIOContext)
import FFmpegKit  // AVIOInterruptCB (inherited interrupt chain)

// LimitCountPreLoadIOContext — a LimitPreLoadIOContext (1C.7) that additionally caps the
// number of "load-more" rounds. Reconstructed inline (deterministic): 2 own fields + a
// delegating init. All other fields/methods are inherited.
//   fields — reflection order [maxMoreCount, moreCount]; both 2-byte stores in the init
//            → UInt16 (⚑ unmapped — width-inferred). moreCount defaults 0.
//   init   — s3 @101ba26c4 (READABLE, flattened): stores moreCount=0, maxMoreCount=param,
//            then (compiler-flattened) the LimitPreLoad + PreLoadIOContext field defaults
//            and finally CacheIOContext's designated init. In Swift those ancestor defaults
//            belong to their own declarations → this init sets only maxMoreCount + delegates
//            to LimitPreLoadIOContext's designated init. Arity/param-order inferred (no init
//            symbol); the maxMoreCount store + super-delegation are explicit in the decompile.
public class LimitCountPreLoadIOContext: LimitPreLoadIOContext {
    // maxMoreCount: cap on load-more rounds. init = param (2-byte store). ⚑
    // Session 62 RESOLVED the session-61 `let` refusal for maxMoreCount: its `= 0` default was
    // always overwritten by the designated init (which assigns the `maxMoreCount` PARAMETER —
    // not expressible in a declaration initializer), so the default was never observable and
    // the faithful `let` form drops it. Binding now matches the FieldRecord (flags 0x00000000).
    let maxMoreCount: UInt16  // ⚑ (width-inferred 2-byte; gate UNCHECKED)
    // moreCount: rounds used so far. init 0 (2-byte store). ⚑
    var moreCount: UInt16 = 0 // ⚑ (width-inferred 2-byte; gate UNCHECKED)

    init(maxMoreCount: UInt16, download: URLContextDownload?, cacheKey: String,
         bufferSize: Int32 = 32 * 1024, saveFile: Bool, isReadComplete: Bool,
         maxFileSize: UInt64, maxReadedFileSize: UInt64) {
        self.maxMoreCount = maxMoreCount   // binary s3: self.maxMoreCount = param; moreCount defaults 0
        super.init(download: download, cacheKey: cacheKey, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete,
                   maxFileSize: maxFileSize, maxReadedFileSize: maxReadedFileSize)
    }
}
