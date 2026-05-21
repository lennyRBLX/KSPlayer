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
//  Case set inferred from the protocol surface (no `get_enum_values` data is
//  available — Ghidra has not promoted the case payload to a typed enum). The
//  two observable axes are vertical and horizontal; refine when a switch /
//  comparison decompile is available.
//

import Foundation

public enum KSPanDirection: Int, CaseIterable, Codable, Sendable {
    case horizontal = 0
    case vertical = 1
}
