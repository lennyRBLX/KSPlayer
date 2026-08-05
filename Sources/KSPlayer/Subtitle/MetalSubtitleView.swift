//
//  MetalSubtitleView.swift
//  KSPlayer
//
//  Forward 1.3.17 — NEW Metal subtitle-overlay view (P4 M1 structure). §8.3. Bodies → P4 M2.
//
import Combine
import CoreGraphics
import Foundation
import MetalKit

// MetalDrawable — KSPlayer protocol (§8.6, descriptor-named). ⚑ requirements → P4 M2 (marker assumed for the M1 compile).
protocol MetalDrawable {}

// MetalSubtitleView @0x1039f229c — :MTKView (superclass-read So7MTKViewC). 7 fields reflection-ordered,
// types §8.3/§8.6. Bodies → P4 M2.
// FIELD-OFFSET GLOBALS, s109 — recorded because deriving this cost a full pass and the obvious
// shortcut is WRONG. This class's seven offset globals are 0x1044ef5a8, 5b8, 5c0, 5c8, 5d0, 5d8
// and 5e0 (exactly seven references across the class's code, matching the seven field records),
// and its field-offset vector @0x1044230b8 gives offsets 0x8, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58.
// The globals are NOT in field order, so pairing the two ascending sequences produces a wrong map:
//   · 0x5a8 -> metalDrawable  and  0x5b8 -> dynamicRange are trie-pinned by their `vpWvd` symbols.
//   · 0x5b8 is initialised with `strb wzr` — a one-byte store — confirming the enum.
//   · 0x5d0 -> cancellables, NOT the 0x38-by-position candidate: the init stores __got 0x104112d10
//     there, which bind_oracle names `__swiftEmptySetSingleton`. The three array fields get
//     0x104112d00 (__swiftEmptyArrayStorage) and a Dictionary would get 0x104112d08 — the three
//     singletons are adjacent and distinguishing them is the whole trick.
//   · 0x5e0 -> playRatio: its init store is the immediate 0x3ff0000000000000, i.e. 1.0.
// ⚠️ STILL OPEN: {0x5c0, 0x5c8, 0x5d8} -> {subtitleImages, pendingTexts, parts} in an order the
//   binary has not yet been made to say. All three are `[…]` initialised from the same empty-array
//   singleton, so nothing at the init distinguishes them, and neither the export trie nor the field
//   records order the globals. `mtkView(_:drawableSizeWillChange:)` @0x101ac0a90 shows 0x5d8 is the
//   INPUT to the private layout helper @0x101abc398 and that the helper's two returned words are
//   stored to 0x5c0 and 0x5c8 — so 0x5d8 is the source list and the other two are derived — but
//   0x101abc398 is not in the trie, so typing its parameters and return is the unit that closes
//   this. Do NOT guess the three from field order.
// ⚑[tool=bind_oracle ref=__got:0x104112d10 result=__swiftEmptySetSingleton]
// ⚑[tool=field_offset_vector ref=MetalSubtitleView:0x1044230b8 result=offsets-0x8-0x30-0x38-0x40-0x48-0x50-0x58]
class MetalSubtitleView: MTKView {
    public var metalDrawable: (any MetalDrawable)? // §8.6 — offset global 0x1044ef5a8 (vpWvd)
    public var dynamicRange: DynamicRange = .sdr // ⚑ default inferred → M2; offset global 0x1044ef5b8 (vpWvd)
    private var cancellables: Set<AnyCancellable> = [] // offset global 0x1044ef5d0 (empty-set singleton)
    private var subtitleImages: [SubtitleImageInfo] = [] // ⚑ offset global one of 0x5c0/0x5c8/0x5d8
    private var pendingTexts: [SubtitleTextInfo] = [] // ⚑ offset global one of 0x5c0/0x5c8/0x5d8
    private var parts: [SubtitlePart] = [] // ⚑ offset global one of 0x5c0/0x5c8/0x5d8
    private var playRatio: Double = 1 // offset global 0x1044ef5e0 (init stores 1.0)
    // ⚑ init shape inferred → M2 witness-verify (real init wires the Metal device + Combine subscriptions)
    override init(frame frameRect: CGRect, device: (any MTLDevice)?) {
        super.init(frame: frameRect, device: device)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    // ⚑ UNRESOLVED → P4 M2: the Metal subtitle render bodies
}
