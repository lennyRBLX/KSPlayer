//
//  SubtitleActor.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — SubtitleActor at 0x101374BCC
//  Swift actor for thread-safe subtitle state management. Actor isolation serializes
//  parts mutations from background decode and reads from main-thread display.
//

import Foundation

/// Thread-safe subtitle state container using Swift actor isolation.
///
/// Wraps subtitle parts and track info so that background decode tasks and
/// main-thread display reads are serialized without explicit locking.
///
/// RE: 136-byte actor with DefaultActorStorage + parts + info fields.
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
    /// RE: SubtitleModel_removeNonMatchingSubtitleParts at 0x10137759C
    public func removeParts(notMatching time: TimeInterval) {
        parts.removeAll { part in
            part.end < time
        }
    }
}
