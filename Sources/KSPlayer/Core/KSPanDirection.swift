//
//  KSPanDirection.swift
//  KSPlayer
//
//  Forward addition (RE): direction discriminator passed by the KSSliderDelegate
//  pan-gesture protocol surface. Both the `Components.VerticalPanGestureView`
//  and the seek-bar slider use this to encode which axis a pan is travelling
//  along before dispatching the per-axis handler.
//
//  Binary: `enum KSPlayer.KSPanDirection` (types.json kind=enum, fields=[])
//  Mangled token `KSPanDirectionO` confirmed at the following protocol method
//  signatures (Swift mangled strings in the binary):
//    `panGestureBegan(location:direction:) (CGPoint, KSPanDirection) -> ()`
//      @ 0x10473ed99
//    `panGestureChanged(velocity:direction:) (CGPoint, KSPanDirection) -> ()`
//      @ 0x10473f817
//    `panValue(velocity:direction:currentTime:totalTime:)
//        (CGPoint, KSPanDirection, Float, Float) -> Float`
//      @ 0x1047385af
//
//  Case set is DEFINITIVE (verified 1.3.15): `ENUM_CASES_1.3.15.md` (Swift
//  reflection field-descriptor dump) records exactly 2 cases — `horizontal = 0`,
//  `vertical = 1`. The raw-value assignment is independently confirmed by the
//  axis-disambiguation disassembly at `0x10150a398`–`0x10150a3b0`
//  (`VideoPlayerView.panGestureDirection_impl`):
//      fabs  d0, d9      ; abs(velX)
//      fabs  d1, d8      ; abs(velY)
//      fcmp  d1, d0      ; abs(velY) >= abs(velX)?
//      cset  w8, pl      ; w8 = 1 when abs(velY) >= abs(velX), else 0
//      strb  w8, [x20, x9] ; self.scrollDirection = w8
//  Thus `horizontal = 0` (seek) and `vertical = 1` (volume/brightness), with
//  vertical winning on a tie (`cset pl` is plus-or-zero). This supersedes the
//  earlier "inferred from protocol signatures" status — no refinement pending.
//

import Foundation

public enum KSPanDirection: Int, CaseIterable, Codable, Sendable {
    case horizontal = 0
    case vertical = 1
}
