//
//  DisplayLinkProtocol.swift
//  KSPlayer
//

import Foundation
import QuartzCore

// DisplayLinkProtocol abstracts UIKit's CADisplayLink (iOS/tvOS/visionOS) and the CVDisplayLink-backed macOS
// shim (the `CADisplayLink` class in MetalPlayView.swift) behind one interface, so MetalPlayView.displayLink can
// hold either. Reconstructed from the binary protocol descriptor @0x1039ee41c (class-bound = AnyObject; 13
// witness requirements; iOS conformance WT @0x1041d64d0). NOTE (binary-indifferent): timestamp/duration are 2 of
// CADisplayLink's 3 get-only timing properties {timestamp, duration, targetTimestamp} — protocol requirement
// names are absent from Swift metadata and these two getter witnesses are dead-stubbed, so the exact pair (and
// their order) is not binary-observable; any 2 recompile to the identical witness table. {timestamp, duration}
// chosen as the primitives (targetTimestamp = timestamp + duration, the shim's derived convenience).
protocol DisplayLinkProtocol: AnyObject {
    var isPaused: Bool { get set }                             // witness i0-2 (i1 set = setPaused:)
    var preferredFramesPerSecond: Int { get set }             // witness i3-5 (dead-stubbed: the pre-iOS-15 fps branch)
    var preferredFrameRateRange: CAFrameRateRange { get set }  // witness i6-8 (i7 set = setPreferredFrameRateRange:)
    var timestamp: TimeInterval { get }                       // witness i9  (binary-indifferent, see note)
    var duration: TimeInterval { get }                        // witness i10 (binary-indifferent, see note)
    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) // witness i11 (called concretely in init)
    func invalidate()                                         // witness i12 (= invalidate)
}

// One unguarded conformance covers both platforms: on iOS/tvOS/visionOS `CADisplayLink` is UIKit's (its native
// properties satisfy every requirement); on macOS it is the CVDisplayLink-backed shim (whose members do). Either
// way an empty extension. Binary iOS conformance WT @0x1041d64d0 (10 dead-stubbed + 3 live witnesses:
// setPaused: / setPreferredFrameRateRange: / invalidate).
extension CADisplayLink: DisplayLinkProtocol {}
