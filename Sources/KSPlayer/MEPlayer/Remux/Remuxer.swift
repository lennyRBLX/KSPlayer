//
//  Remuxer.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction — P2 remux cluster (Wave 2). NEW Forward-only class (root, no superclass).
//  The packet-writer that fronts OutputStreamInfo: per packet it clamps the DTS, records it, then drives
//  the per-stream Copy/BSF builder (OutputStreamInfo slot13). Reconstructed FAITHFUL from write/slot7
//  (0x101a65df0, 94 instr). Descriptor 0x1039f01e8, accessor 0x101a6608c.
//
//  `final` not binary-pinned (no library evolution) — M2 verifies; matches the Copy/BSF/OSI `final` choice.
//
import AVFoundation   // AVMediaType — see the mediaType field: unqualified it resolves to Libavutil's C enum
import Foundation
import Libavcodec
import Libavformat

public final class Remuxer {
    // 5 stored fields — reflection-authoritative NAMES + ORDER; offsets from the driver store-sequence (size 0x34).
    let formatCtx: UnsafeMutablePointer<AVFormatContext>  // +0x10 ⚑ inferred (symref); driver stores formatContext[+0x18];
                                                          //   matches the 1C.5 FormatContext convention (OSI.formatCtx is exactly this)
    let outputStreamInfo: OutputStreamInfo               // +0x18  grounded (write reads it; the P3 builder returns OSI here)
    // ⚑ MODULE-QUALIFIED s102. Unqualified, `AVMediaType` resolved HERE to Libavutil's C enum, because
    //   this file imports Libavcodec/Libavformat and not AVFoundation — a silent wrong type, since the
    //   binary `objc_retain`s this field (@0x101a484b4, stored `str x21,[x23,#0x20]` @0x101a484b0) and
    //   a C enum is not retainable. The value arrives from MEPlayerItem.startRecord, whose trie
    //   signature types it `__C.AVMediaType?` (mangled `So07AVMediaH0aSg`, an `a`-kind typealias).
    //   ⚑[tool=export_trie_oracle ref=MEPlayerItem.startRecord(url:mediaType:):0x101a483d4 result=AVMediaType-optional]
    let mediaType: AVFoundation.AVMediaType?              // +0x20  l2_field_gate property-symbol (class-proven) = AVMediaType? (OPTIONAL)
    var startTime: [Int32: Int64] = [:]                  // +0x28  per-stream DTS map. CLASS-SCOPED field-record = SDy (DICTIONARY),
                                                         //   key Int32 (stream_index), value Int64 (clamped DTS) — corroborated by write()'s
                                                         //   keyed-set. NOT Array, NOT CMTime?, NOT Double: l2_field_gate's `Double` is an
                                                         //   UNSCOPED property-symbol match (another class's startTime); the class-scoped
                                                         //   field-record + write-usage are authoritative (§19). ⚑ key/value width via §7-walled symref
    var lock: os_unfair_lock = os_unfair_lock()          // +0x30  (4-byte os_unfair_lock, init 0)

    // init — minimal inferred (devirt slot6, inlined in the P3 driver → signature UNRECOVERABLE).
    // ⚑ init inferred — devirt slot6, built inline by the P3 driver 0x101a483d4 (alloc+field-stores);
    //   exact signature unrecoverable.
    public init(formatCtx: UnsafeMutablePointer<AVFormatContext>,
                outputStreamInfo: OutputStreamInfo,
                mediaType: AVFoundation.AVMediaType?) {
        self.formatCtx = formatCtx
        self.outputStreamInfo = outputStreamInfo
        self.mediaType = mediaType
        // startTime defaults to [:]; lock defaults to os_unfair_lock().
    }

    // ── write (slot7 @0x101a65df0, 94 instr) — FAITHFUL (DTS-clamp + lock + → slot13) ─────────────
    // NAME IS INVENTED AND IS NOW MARKED AS SUCH. `name_exhaustion_gate` closes ALL SEVEN routes on
    //   0x101a65df0 — no trie symbol at the address; the trie carries NO symbol for class
    //   KSPlayer.Remuxer at all (its only Remuxer-bearing symbols are MEPlayerItem's `remuxer` field
    //   and two unrelated ProAVPlayer protocol descriptors); no `#function`/`#file` literal (the body
    //   has ZERO string literals); not an objc selector or IMP; and `masked_twin --scan` finds no twin
    //   anywhere in the image, so it is real source, not emitted-library code. Two call sites, so it
    //   is not INLINE-INSTEAD. Exactly one data pointer references it image-wide: Remuxer's metadata
    //   vtable slot 7 (0x1044eae58 = meta 0x1044eada8 + 0x78 + 0x38) — no witness table, no objc
    //   method list, so the witness-anchoring route is closed too.
    // ⚠️ THE VTABLE-ELIMINATION ROUTE IS CLOSED ON THE MERITS, NOT ON THE GATE'S SAY-SO. The gate
    //   reported "3 slots are unnamed" for this class; that is a TOOL BUG (its regex
    //   `0x([0-9a-f]{9})` also matches the two header addresses `desc=0x1039f01e8` and
    //   `@0x1039f0214` that vtable_walk prints, so it counted headers as impls — the true Impl count
    //   is 1). Corrected, the route would print OPEN, and that OPEN would be VACUOUS: elimination
    //   needs N-1 NAMED siblings and the trie names zero Remuxer methods. Closed either way.
    // ⚠️ THE NAME IS KEPT, NOT CHANGED. `transcode(packet:)` is the binary's convention for this exact
    //   AVPacket-ingest signature (FFmpegAssetTrack and OutputStreamInfo both use it; no trie-named
    //   KSPlayer member with an AVPacket parameter is called `write`). But that is a convention
    //   argument at a DIFFERENT abstraction level — this is the Remuxer's entry point, and the actual
    //   output write happens downstream in the transcode contexts — and swapping one invented name
    //   for another invented name buys
    //   no binary evidence. What was actually wrong here is that a fabricated identifier carried
    //   prose instead of the marker grammar, so no grep could find it. That is fixed.
    //   Header-verified AVPacket offsets: pts@+0x08, dts@+0x10, stream_index@+0x24.
    // ⚑[invented=write addr=0x101a65df0 exhaustion=name_exhaustion_gate approved=jweaver]
    func write(_ packet: UnsafeMutablePointer<AVPacket>) {
        // Guard [A]: the OSI must have stream mappings. *(*(*(self+0x18)+0x40)+0x10) != 0 →
        // outputStreamInfo.streamMapping (OSI+0x40), NOT transcodeMap (OSI+0x18). [orchestrator re-walk fix]
        guard !outputStreamInfo.streamMapping.isEmpty else { return }

        let idx = packet.pointee.stream_index                          // packet+0x24
        // Guard [B]: this stream must be mapped to an output. subscript FUN_1019c10ec → (param_2 & 1).
        // ⚑ [B] binding inferred as streamMapping[idx] (consistent with guard [A]'s streamMapping check).
        guard outputStreamInfo.streamMapping[idx] != nil else { return }

        os_unfair_lock_lock(&lock)                                     // self+0x30
        defer { os_unfair_lock_unlock(&lock) }                         // self+0x30 (binary unlocks on the same path tail)

        // Record the clamped DTS for this stream IF not already recorded. Binary: `if startTime empty ||
        // startTime[idx] miss { … }` (self+0x28: isUniquelyReferenced + keyed-set FUN_1019c235c + the
        // 0x8000000000000000 sentinel swap). startTime (self+0x28) is the Remuxer's OWN [Int32: Int64]
        // DTS map (field-record SDy). DTS clamp = min(max(pts,0), max(dts,0)); the binary computes max(x,0)
        // branchlessly as `x & ~(x>>63)` for pts (packet+0x08) and dts (packet+0x10), then min.
        if startTime[idx] == nil {                                     // self+0x28 empty OR subscript-miss
            let pts = packet.pointee.pts                               // packet+0x08
            let dts = packet.pointee.dts                               // packet+0x10
            startTime[idx] = min(max(pts, 0), max(dts, 0))            // keyed-set FUN_1019c235c on self+0x28
        }

        // Ensure the per-stream context exists and RUN it (OSI.s13). The completion is the write-output
        // callback: ctx.transcode produces the filtered/copied packet, then calls completion(outputPacket)
        // to emit it. Binary: callback FUN_101a660d0 + a closure box capturing self+idx (DAT_1041d9368).
        outputStreamInfo.buildTranscodeContext(packet) { [self] outputPacket in   // FUN_101a1ab5c (File-1 slot13)  ⚑[tool=resolve_fun_pins ref=FUN_101a1ab5c:0x101a1ab5c result=RESOLVES_UNIQUELY] = KSPlayer.OutputStreamInfo.transcode(packet: Swift.UnsafeMutablePointer<__C.AVPacket>, block: ((Swift.UnsafeMutablePointer<__C.AVPacket>) -> ())?) -> Swift.Int32
            writeOutputPacket(outputPacket, streamIndex: idx)
        }
    }

    // ⚑ UNRESOLVED → P3: write-output completion body (FUN_101a660d0). Emits the transcoded `outputPacket`
    // to the output format context for `streamIndex` (av_write_frame / av_interleaved_write_frame — the actual
    // write is devirtualized/unresolved). NOT invented. Reconstruct as its own unit (decompile FUN_101a660d0).
    private func writeOutputPacket(_ outputPacket: UnsafeMutablePointer<AVPacket>?, streamIndex: Int32) {
        // UNRESOLVED — devirtualized write-output (FUN_101a660d0); reconstruct as its own unit.
    }

    // slot8 — devirtualized, no readable body.
    // UNRESOLVED → P3: slot8 (devirt, no body)
}
