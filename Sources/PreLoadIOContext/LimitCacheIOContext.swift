import Foundation
import KSPlayer   // AbstractAVIOContext (superclass chain via CacheIOContext)

// LimitCacheIOContext — CacheIOContext (1C.7) + a single maxFileSize cap. Reconstructed
// inline (deterministic): 1 own field + a delegating init. All other fields/methods are
// inherited from CacheIOContext.
public class LimitCacheIOContext: CacheIOContext {
    // maxFileSize: byte cap for this cache context. init stores param (8-byte) → UInt64.
    public var maxFileSize: UInt64 = 0 // ⚑ (field-record unmapped; UInt64 by width + position-field pattern)

    // s3 @101b9c388 → inner FUN_101b9c388: stores maxFileSize (explicit) then delegates to
    //   CacheIOContext's designated init. The maxFileSize store + super-delegation are
    //   explicit in the decompile.
    // ⚑[tool=export_trie_oracle ref=FUN_101b86d38:0x101b86d38 result=IDENTIFIED as $s16PreLoadIOContext05CacheC0C8download3md510bufferSize8saveFile14isReadCompleteAC8KSPlayer16DownloadProtocol_p_SSs5Int32VS2btKcfc — CacheIOContext's designated init, INITIALIZING entry (`cfc`). It was a raw FUN_ only because the class name is word-substituted]
    // Labels AND parameter order are now RECOVERED, not inferred — the comment here used to
    // read "Arity/param-order inferred (no mangled init symbol)". There IS a mangled init
    // symbol; it was unreachable because the class name is word-substituted (`010LimitCacheC0C`).
    // Both facts it asserted were wrong: the label is `md5:`, and `maxFileSize` is the FIFTH
    // parameter, not the first.
    // ⚑[tool=export_trie_oracle ref=$s16PreLoadIOContext010LimitCacheC0C8download3md510bufferSize8saveFile03maxkI014isReadCompleteAC8KSPlayer16DownloadProtocol_p_SSs5Int32VSbs6UInt64VSbtKcfc result=labels+order RECOVERED]
    public init(download: URLContextDownload?, md5: String,
                bufferSize: Int32 = 32 * 1024, saveFile: Bool, maxFileSize: UInt64,
                isReadComplete: Bool) {
        self.maxFileSize = maxFileSize
        super.init(download: download, md5: md5, bufferSize: bufferSize,
                   saveFile: saveFile, isReadComplete: isReadComplete)
    }
}
