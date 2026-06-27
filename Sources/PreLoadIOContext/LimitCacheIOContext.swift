import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via CacheIOContext)

// LimitCacheIOContext — CacheIOContext (1C.7) + a single maxFileSize cap. Reconstructed
// inline (deterministic): 1 own field + a delegating init. All other fields/methods are
// inherited from CacheIOContext.
public class LimitCacheIOContext: CacheIOContext {
    // maxFileSize: byte cap for this cache context. init stores param (8-byte) → UInt64.
    var maxFileSize: UInt64 = 0 // ⚑ (field-record unmapped; UInt64 by width + position-field pattern)

    // s3 @101b9c388 → inner FUN_101b9c388: stores maxFileSize (explicit) then delegates to
    //   CacheIOContext's designated init (FUN_101b86d38). Arity/param-order inferred (no
    //   mangled init symbol); the maxFileSize store + super-delegation are explicit in the
    //   decompile. Forwards CacheIOContext's designated params unchanged.
    public init(maxFileSize: UInt64, download: URLContextDownload?, cacheKey: String,
                bufferSize: Int32 = 32 * 1024, saveFile: Bool, isReadComplete: Bool) {
        self.maxFileSize = maxFileSize
        super.init(download: download, cacheKey: cacheKey, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete)
    }
}
