//
//  CachedTimeRange.swift
//  KSPlayer
//
//  Forward addition (RE): contiguous-byte-range descriptor for the
//  buffered-content rail on the seek bar. Consumed by
//  `Components.PlayerViewModel.TimeInfo._cachedRanges` and by the SwiftUI
//  buffer overlay.
//
//  Binary: `struct KSPlayer.CachedTimeRange` (2 fields per types.json):
//    start: Double
//    end:   Double
//

import Foundation

public struct CachedTimeRange: Equatable, Hashable, Codable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var duration: Double { end - start }
}
