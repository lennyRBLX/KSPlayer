//
//  ASSImage.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — ASSImage_linkedListToArray at 0x1014734bc
//  Helper that converts the libass ASS_Image singly-linked list (`->next`)
//  into a Swift Array of value-typed elements, decoupling the rendering
//  paths in AssImageRenderer / AssIncrementImageRenderer / LibassSubtitleRenderer
//  from the raw C linked-list traversal.
//

import CoreGraphics
import Foundation
import Libass

/// Helper namespace around libass `ASS_Image` linked-list traversal.
///
/// The Forward binary has a dedicated `ASSImage` class with a single
/// member function (`linkedListToArray @ 0x1014734bc`) that walks the
/// `ASS_Image::next` chain returned by `ass_render_frame` and emits a
/// Swift `Array<ASS_Image>` value-typed copy. Several call sites in
/// `AssImageRenderer_renderSubtitleFrame` then consume the array
/// instead of re-walking the linked list.
///
/// This Swift reconstruction provides the same conversion plus a small
/// value-typed wrapper so consumers do not have to handle the raw
/// `UnsafeMutablePointer<ASS_Image>` API.
public enum ASSImage {
    /// Value-typed snapshot of one `ASS_Image` node from the libass chain.
    public struct Layer: Sendable, Hashable {
        public let dstX: Int32
        public let dstY: Int32
        public let width: Int32
        public let height: Int32
        public let stride: Int32
        /// 0xRRGGBBAA — the libass `ASS_Image::color` field as carried in the
        /// binary. The low byte is the ASS inverted-alpha value
        /// (0 = opaque, 0xFF = transparent).
        public let color: UInt32
        /// Raw bitmap pointer; valid only for the lifetime of the
        /// originating render call. Consumers that need to outlive the
        /// libass frame must copy.
        public let bitmap: UnsafePointer<UInt8>?

        public init(_ img: ASS_Image) {
            dstX = img.dst_x
            dstY = img.dst_y
            width = img.w
            height = img.h
            stride = img.stride
            color = img.color
            bitmap = UnsafePointer(img.bitmap)
        }

        public var frame: CGRect {
            CGRect(x: Int(dstX), y: Int(dstY), width: Int(width), height: Int(height))
        }

        /// ASS inverted-alpha convention: 0 = fully opaque, 0xFF = fully
        /// transparent. The decoded byte returned here is suitable for
        /// direct `vImage`/`CGContext` blending.
        public var opacity: UInt8 {
            UInt8(~(color & 0xFF) & 0xFF)
        }
    }

    /// Walk `head->next->next...` and return a value-typed snapshot of
    /// every node. Returns an empty array when `head` is nil.
    ///
    /// RE: ASSImage_linkedListToArray at 0x1014734bc
    public static func linkedListToArray(_ head: UnsafeMutablePointer<ASS_Image>?) -> [Layer] {
        var result: [Layer] = []
        var node = head
        while let current = node {
            result.append(Layer(current.pointee))
            node = current.pointee.next
        }
        return result
    }

    /// Compute the union bounding box of every layer with a non-zero
    /// width/height. Returns `nil` when there are no positive-extent
    /// layers (i.e. nothing to draw).
    public static func boundingBox(of layers: [Layer]) -> CGRect? {
        var minX = Int32.max, minY = Int32.max
        var maxX = Int32.min, maxY = Int32.min
        for layer in layers where layer.width > 0 && layer.height > 0 {
            minX = min(minX, layer.dstX)
            minY = min(minY, layer.dstY)
            maxX = max(maxX, layer.dstX + layer.width)
            maxY = max(maxY, layer.dstY + layer.height)
        }
        guard minX < maxX, minY < maxY else { return nil }
        return CGRect(
            x: Int(minX),
            y: Int(minY),
            width: Int(maxX - minX),
            height: Int(maxY - minY)
        )
    }
}
