import Foundation

// Forward-only protocol pair, both module KSPlayer, both recovered in s98.
//
// PreLoadProtocol             `$s8KSPlayer15PreLoadProtocolMp`                    @0x1039ede48
// PreLoadPlaybackPositionSync `$s8KSPlayer35PreLoadPlaybackPositionSyncProtocolMp` @0x1039edea8
//
// Note the length token on the second one is 35, not 37. A hand-built probe with the wrong
// count returns a plausible-looking "NOT IN TRIE", which is indistinguishable from a real
// negative — count the identifier rather than estimating it.
//
// NEITHER IS CLASS-CONSTRAINED. protocol_signature reports NumRequirementsInSignature 0 for
// both, so neither carries a Layout requirement on Self and neither may be written
// `: AnyObject`. (Contrast DisplayEnum, which reports 1 and IS class-constrained.) Neither
// has an associated type, so no requirement type is an abstract placeholder.
//
// Conformers, all witness tables validated by decode_witness_table:
//   PreLoadProtocol             <- LimitSeparatePreLoadIOContext  wt 0x1041e21b0
//                               <- PreLoadIOContext               wt 0x1041e2250
//   PreLoadPlaybackPositionSync <- PreLoadIOContext               wt 0x1041e22a0
//
// HOW THE NAMES AND TYPES WERE ESTABLISHED. Every one of the ten witness addresses in those
// three tables is NOT_IN_TRIE, so none of these names came from a witness. They were read
// off the CONFORMERS' own exported method symbols, found by dumping the whole orphan export
// trie (57138 mangled names) and searching the DEMANGLED text — e.g.
// `PreLoadIOContext.PreLoadIOContext.cachedTimeRanges(duration: Swift.Double) ->
// [KSPlayer.CachedTimeRange]`. The requirement ORDER below is the witness-table order, and
// the KINDS independently corroborate it: protocol_signature reports
// Getter,Getter,Getter,Getter,Method,Getter,Method,Method,Method, which is exactly the
// shape of the nine declarations as written.
//
// THE CONFORMANCES ARE NOT DECLARED YET, and that is deliberate rather than an oversight.
// Swift will not accept a conformance whose witnesses do not exist, and several of these
// members are absent from both conformers under any spelling — `more()` alone is 1183
// instructions on PreLoadIOContext and 433 on LimitSeparatePreLoadIOContext. Declaring the
// members with invented bodies to satisfy the compiler would be exactly the fabrication the
// reconstruction rules forbid, so the protocols land first and each conformance follows its
// members. Until then superclass_conformance_gate continues to FLAG both conformer files,
// which is the honest state.
public protocol PreLoadProtocol {
    // 0
    var loadedSize: Int64 { get }
    // 1 — shared witness ADDRESS, but see the correction below: an ICF fold, not a default.
    var position: UInt64 { get }
    // 2 — shared witness address; same correction.
    var downloadSpeed: Double { get }
    // 3 — shared witness address; same correction.
    var bytesRead: UInt64 { get }
    // 4
    func more() -> Int32
    // 5
    var timeIndex: [TimeIndexEntry] { get }
    // 6
    func addTimeIndex(position: UInt64, time: Double)
    // 7
    func cachedTimeRanges(duration: Double) -> [CachedTimeRange]
    // 8 — note the sibling protocol below declares a DIFFERENT overload of this name.
    func syncPlaybackPosition(time: Double, duration: Double)
}

// CORRECTION, and it is worth stating plainly because the first reading of this was wrong.
//
// Requirements 1, 2 and 3 resolve to the SAME witness address in BOTH conformance tables —
// req1 0x101ba66bc, req2 0x101b95bf8 (thunk -> 0x101b914d0), req3 0x101a65dd4 (thunk ->
// 0x101a63dec). That was first read as proof of protocol-extension defaults, on the reasoning
// that two unrelated conformers cannot share a witness body. THAT REASONING IS INVALID, and
// the bodies themselves refute it: req2's shared body is
//     ldr x8, [x20]  ·  ldr d0, [x8, #0x68]  ·  ret
// — a CONCRETE read of inherited offset 0x68, which is CacheIOContext._downloadSpeed, whose
// own exported getter @0x100d362bc is the same `ldr d0, [x20, #0x68]`. req3's body likewise
// reads offset 0x18 = CacheIOContext.bytesRead, and req1's reads 0x50 and 0x80 = urlPos and
// logicalPos. A generic protocol-extension body cannot hardcode an inherited stored-property
// offset.
//
// The two conformers are SIBLINGS under CacheIOContext, not one under the other, so they
// inherit an identical layout and their witnesses come out bit-identical — and the linker
// folds them. The shared address is an ICF fold, exactly the case AGENT_PROTOCOL warns about:
// a shared address is not an anchor mismatch, the code is genuinely each function's, it is
// merely also somebody else's.
//
// Protocol-extension defaults for two of these DO exist — the trie carries
// `(extension in KSPlayer):KSPlayer.PreLoadProtocol.downloadSpeed.getter` @0x10002dc44 and
// `...bytesRead.getter` @0x1001a1394 — but at addresses appearing in NEITHER witness table, so
// neither conformer uses them. No `position` or `loadedSize` extension default exists at all
// (both real trie negatives).
//
// The consequence for the conformances: these three are satisfied by members INHERITED from
// CacheIOContext, not by anything the protocol supplies. Source's CacheIOContext already has
// `bytesRead`; it does not yet have `downloadSpeed` (only the private stored `_downloadSpeed`
// at the same 0x68) or `position`.
// ⚑[tool=decode_witness_table ref=KSPlayer.PreLoadProtocol:0x1039ede48 result=reqs-1-2-3-ICF-folded]

// Sole requirement, and it is NOT a duplicate of PreLoadProtocol's req8 — it is a different
// overload of the same base name, distinguished by its second label and type. Both exist as
// separate symbols on the same class:
//   PreLoadIOContext.PreLoadIOContext.syncPlaybackPosition(time: Double, duration: Double)
//   PreLoadIOContext.PreLoadIOContext.syncPlaybackPosition(time: Double, position: UInt64?)
// Sole conformer PreLoadIOContext, wt 0x1041e22a0, whose single witness is 0x1002e67c0.
public protocol PreLoadPlaybackPositionSyncProtocol {
    func syncPlaybackPosition(time: Double, position: UInt64?)
}
