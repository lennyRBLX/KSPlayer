//
//  AssLayer.swift
//  KSPlayer
//
//  Forward 1.3.17 ASS-blend bitmap layer model (P4 M1 structure) — the BitmapSource payload.
//  Binary-decoded (spec §8 s14); pointer/color/vector types inferred (GOT-indirect) → M2 verify.
//
import CoreGraphics
import Foundation
import Metal

// LayerType @0x1039f21b0 — cases descriptor-confirmed
public enum LayerType {
    case character
    case outline
    case shadow
    case other
}

// AssLayer @0x1039f2194
public struct AssLayer {
    public var bitmap: UnsafeMutablePointer<UInt8>?   // ⚑ pointer inferred (raw ASS bitmap) → M2 verify
    public var color: UInt32                          // ⚑ inferred (packed color word) → M2 verify
    public var type: LayerType
    public var w: Int
    public var h: Int
    public var stride: Int
    public var dstX: Int
    public var dstY: Int
}

// AssLayerSource @0x1039f23bc
public struct AssLayerSource {
    public var bitmap: UnsafeMutablePointer<UInt8>?   // ⚑ pointer inferred
    public var width: Int
    public var height: Int
    public var stride: Int
    public var origin: SIMD2<Float>                   // ⚑ <Float>-generic (mangle `<?>ySfG`) inferred → M2 verify
    public var size: SIMD2<Float>                     // ⚑ inferred
    public var color: SIMD2<Float>                    // ⚑ inferred — may be SIMD4<Float> (RGBA); M2 verify
}

// BitmapSource @0x1039f2178 — cases + payloads decoded (was NOT an empty/simple enum)
public enum BitmapSource {
    case assBlend(layers: [AssLayer], boundingRect: CGRect)
    case palette(bitmap: UnsafeMutablePointer<UInt8>?, palette: UnsafeMutablePointer<UInt8>?, width: Int, height: Int, stride: Int)   // ⚑ pointers inferred
    case prerendered(any MTLTexture)
}
