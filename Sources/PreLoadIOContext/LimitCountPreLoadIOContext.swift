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
    private var moreCount: UInt16 = 0 // ⚑ (width-inferred 2-byte; gate UNCHECKED)

    // Labels AND order RECOVERED from the word-substituted mangled name (`010LimitCountabC0C`);
    // `maxMoreCount` is the LAST parameter, not the first, and the String label is `md5:`.
    // ⚑[tool=export_trie_oracle ref=$s16PreLoadIOContext010LimitCountabC0C8download3md510bufferSize8saveFile03maxkI00l6ReadedkI014isReadComplete0l4MoreE0AC8KSPlayer16DownloadProtocol_p_SSs5Int32VSbs6UInt64VAQSbs6UInt16VtKcfc result=labels+order RECOVERED]
    // `download` is the EXISTENTIAL `any DownloadProtocol`, not the concrete URLContextDownload.
    // The mangle above spells it `8KSPlayer16DownloadProtocol_p` — the `_p` is what marks an
    // existential, and this very module mangles a concrete one differently
    // (HLSCacheIOContext's init carries `AcA18URLContextDownloadC_`), so the two forms are a
    // distinction the binary itself makes, not a spelling of ours. Proven again inside THIS
    // init's own body rather than inherited from CacheIOContext's note: at 0x101ba26c4 the
    // prologue takes download in x0 as an ADDRESS, and the super-delegation at 0x101ba28e0
    // copies it through the outlined helper 0x1001263e0 and passes `add x0, sp, #0x8` — the
    // address of the copy — to CacheIOContext's designated init @0x101b86d38. That helper
    // moves the metadata word at +0x18 and the witness table at +0x20 and then calls a value
    // witness: a 40-byte existential box. A class reference would be one register value with a
    // swift_retain, never a stack copy whose address is handed on.
    // The register map for the whole parameter list is pinned by the same prologue: x0 download,
    // x1/x2 md5, x3 bufferSize, x4 saveFile, x5 maxFileSize, x6 maxReadedFileSize, w7
    // isReadComplete, and maxMoreCount NINTH, read off the stack with `ldrh w20, [x29, #0x10]`.
    // STILL DIVERGENT — the optionality. The mangle carries no `Sg`, so the binary's parameter
    // is non-optional `any DownloadProtocol` here and in all six PreLoadIOContext inits that
    // take one. Dropping the `?` is blocked, not deferred by choice: CacheIOContext.swift:211
    // and LimitSeparatePreLoadIOContext.swift:346 both delegate with `download: nil` as the
    // explicitly-recorded P8 IO-completion spine, and the real value there is built by the deep
    // FFmpeg URLContext open in 0x101b90c58. Removing the optional would force that construction
    // to be invented. It is its own unit. The existence-check RAN and LOCATED that construction —
    // it is found and characterised, not missing:
    // ⚑[tool=export_trie_oracle ref=$s16PreLoadIOContext18URLContextDownloadC3url5flags7options9interrupt14isReadCompleteAC10Foundation3URLV_s5Int32VSpys13OpaquePointerVSgGSgSo15AVIOInterruptCBVSbtKcfc:0x101b90c58 result=LOCATED]
    init(download: (any DownloadProtocol)?, md5: String,
         bufferSize: Int32 = 32 * 1024, saveFile: Bool,
         maxFileSize: UInt64, maxReadedFileSize: UInt64, isReadComplete: Bool,
         maxMoreCount: UInt16) {
        self.maxMoreCount = maxMoreCount   // binary s3: self.maxMoreCount = param; moreCount defaults 0
        super.init(download: download, md5: md5, bufferSize: bufferSize,
                   saveFile: saveFile, maxFileSize: maxFileSize,
                   maxReadedFileSize: maxReadedFileSize, isReadComplete: isReadComplete)
    }
}
