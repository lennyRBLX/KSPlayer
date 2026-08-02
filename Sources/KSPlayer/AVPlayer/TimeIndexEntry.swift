import Foundation

// TimeIndexEntry — a value type recovered from __swift5_fieldmd (struct; not in the
// class classmap → no vtable). Referenced by PreLoadIOContext._timeIndex and
// LimitSeparatePreLoadIOContext._timeIndex (both `[TimeIndexEntry]`).
//
// s98 — MOVED from the PreLoadIOContext target to KSPlayer. The binary says
// `KSPlayer.TimeIndexEntry`: the trie carries
// `$s8KSPlayer14TimeIndexEntryV8positions6UInt64Vvg` and
// `nominal type descriptor for KSPlayer.TimeIndexEntry`, while the
// `$s16PreLoadIOContext14TimeIndexEntryMn` spelling is a real trie negative. It has to live
// here because `KSPlayer.PreLoadProtocol` names it in a requirement type, and
// PreLoadIOContext depends on KSPlayer rather than the other way round.
//
// s98 — the `position` type pin is DISCHARGED. It was flagged "field-record unmapped; UInt64
// by width + position-field pattern", i.e. a guess from the load width. The trie settles it
// outright: `position.getter : Swift.UInt64` and
// `init(position: Swift.UInt64, time: Swift.Double)`.
//
// Both properties are `let`, not `var`. The image exports a getter for each and NO setter and
// NO modify for either — the same negative that distinguishes them from, say,
// `KSOptions.display`, which carries getter, setter AND modify. Nothing mutates a member in
// place either: the one write site (LimitSeparatePreLoadIOContext.addTimeIndex) replaces the
// whole element with a freshly constructed value.
public struct TimeIndexEntry {
    public let position: UInt64
    public let time: Double

    // Spelled out rather than left to memberwise synthesis: a synthesized memberwise init is
    // `internal`, and this type is now consumed from the PreLoadIOContext module. The binary
    // agrees it is public — the trie exports
    // `init(position: Swift.UInt64, time: Swift.Double) -> KSPlayer.TimeIndexEntry`, and an
    // internal init of an internal-init'd struct would export nothing. The body is a bare
    // `ret` (both fields arrive in registers), i.e. plain memberwise assignment.
    public init(position: UInt64, time: Double) {
        self.position = position
        self.time = time
    }
}

// CachedTimeRange — absent from Sources/ entirely before s98, and required by
// `PreLoadProtocol.cachedTimeRanges(duration:) -> [CachedTimeRange]`. Also
// KSPlayer-module: `nominal type descriptor for KSPlayer.CachedTimeRange`, and both
// KSAVPlayer and KSMEPlayer expose `cachedTimeRanges.getter : [KSPlayer.CachedTimeRange]`.
//
// Members and order are read, not chosen: `init(start: Swift.Double, end: Swift.Double)`
// fixes the declaration order, and the two accessors confirm which register each field
// occupies — `start.getter` is a bare `ret` (the first field is already in d0) while
// `end.getter` @0x1000eef70 is `mov.16b v0, v1` / `ret`, moving the SECOND register into the
// return. Both are `let` by the same no-setter negative as above.
public struct CachedTimeRange {
    public let start: Double
    public let end: Double

    // Public for the same reason and on the same evidence as TimeIndexEntry's: the trie
    // exports `init(start: Swift.Double, end: Swift.Double) -> KSPlayer.CachedTimeRange`.
    // Its body is likewise a bare `ret`.
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    // COMPUTED, and the whole body is two instructions at 0x1019e30f4:
    //   fsub d0, d1, d0   ·   ret
    // With start in d0 and end in d1 that is exactly `end - start`. It carries its own
    // property descriptor and getter but no setter, so it is get-only.
    public var duration: Double {
        end - start
    }
}
