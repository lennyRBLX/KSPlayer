//
//  SubtitleActor.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleActor_createOrUpdateActor at
//  0x1014910a4 (Ghidra entry; older notes used the IDA-era address
//  0x101374BCC, which is interior to a wrapper). Swift actor for
//  thread-safe subtitle state management. Actor isolation serializes
//  `parts` mutations from background decode and reads from
//  main-thread display.
//

import Foundation

/// Thread-safe subtitle state container using Swift actor isolation.
///
/// Wraps subtitle parts and track info so that background decode tasks and
/// main-thread display reads are serialized without explicit locking.
///
/// RE: 136-byte (0x88) actor — confirmed exact via
/// `createOrUpdateActor`'s three ivar writes:
///   - `+0x70`  = parts ref (`emptyArrayStorage`)
///   - `+0x78`  = SubtitleInfo existential object ref
///   - `+0x80`  = SubtitleInfo existential witness table
/// End-of-instance is at `+0x88`. Header (0x10) + DefaultActorStorage
/// (0x60) + parts (0x8) + class-existential pair (0x10) = 0x88.
public actor SubtitleActor {
    /// Currently active subtitle parts for display.
    public private(set) var parts: [SubtitlePart]

    /// Metadata for the active subtitle track.
    public private(set) var info: (any SubtitleInfo)?

    public init() {
        self.parts = []
        self.info = nil
    }

    /// Replace the current parts array (called from decode background tasks).
    public func setParts(_ newParts: [SubtitlePart]) {
        parts = newParts
    }

    /// Append a single decoded part (called from decode pipeline).
    public func appendPart(_ part: SubtitlePart) {
        parts.append(part)
    }

    /// Insert parts in sorted order by start time.
    public func insertSorted(_ newParts: [SubtitlePart]) {
        parts.append(contentsOf: newParts)
        parts.sort { $0.start < $1.start }
    }

    /// Set the active subtitle track info.
    public func setInfo(_ newInfo: (any SubtitleInfo)?) {
        info = newInfo
    }

    /// Search for subtitle parts matching the given time.
    /// Mirrors KSSubtitle.search(for:) with actor isolation.
    public func search(for time: TimeInterval) -> [SubtitlePart] {
        var result = [SubtitlePart]()
        for part in parts {
            if part == time {
                result.append(part)
            } else if part.start > time {
                break
            }
        }
        return result
    }

    /// Clear all parts and info (called on track change or media change).
    public func reset() {
        parts.removeAll()
        info = nil
    }

    /// Remove parts that no longer match the current time window.
    ///
    /// RE: The Forward binary has no standalone "removeNonMatchingSubtitleParts"
    /// function. The Dutch-flag partition + COW work that previously
    /// went under that IDA-era name lives inside
    /// `SubtitleModel_updateActiveSubtitles @ 0x1014956d4`. This actor
    /// helper is a simpler version operating on the actor's own
    /// `parts` slice — Swift's array semantics give us the manual
    /// `_swift_isUniquelyReferenced_nonNull_native` COW handling
    /// automatically.
    public func removeParts(notMatching time: TimeInterval) {
        parts.removeAll { part in
            part.end < time
        }
    }
}
