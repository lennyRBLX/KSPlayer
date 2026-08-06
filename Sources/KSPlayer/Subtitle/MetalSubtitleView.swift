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
// ✅ CLOSED in s112: {0x5c0, 0x5c8, 0x5d8} -> {subtitleImages, pendingTexts, parts}. The note below
//   was right that the ORDER OF THE GLOBALS says nothing — but the VALUE each global holds does, and
//   that is a different reading. Each of these globals stores the field's byte offset, and the
//   field-offset vector @0x1044230b8 assigns those offsets to fields in field-record order:
//     0x5a8 -> 0x8  metalDrawable   0x5b8 -> 0x30 dynamicRange   0x5d0 -> 0x38 cancellables
//     0x5c0 -> 0x40 subtitleImages  0x5c8 -> 0x48 pendingTexts   0x5d8 -> 0x50 parts
//     0x5e0 -> 0x58 playRatio
//   The method is validated ON THIS CLASS by the four anchors that were already known independently
//   (metalDrawable, dynamicRange, cancellables, playRatio): all four land on the offset their own
//   global holds, so the three unknowns are read the same way, not guessed.
//   It also CORROBORATES the semantic reading recorded below: 0x5d8 is `parts`, and `parts` is what
//   `mtkView(_:drawableSizeWillChange:)` feeds to the layout helper @0x101abc398, whose two returned
//   words land in `subtitleImages` and `pendingTexts` — i.e. parts is the source list and the other
//   two are derived from it. Two independent routes, same answer.
//   ⚑[tool=field_offset_vector ref=MetalSubtitleView.subtitleImages:0x1044230b8 result=0x40]
//   ⚑[tool=recover_field_offsets ref=MetalSubtitleView.parts:0x1044ef5d8 result=parts]
//   Still unresolved and still not to be guessed: 0x1044ef5b0 holds offset 0x0, which is no field of
//   this class — the vector has no 0x0 entry — so that global is not a MetalSubtitleView field at all.
//   ⚑[tool=recover_field_offsets ref=MetalSubtitleView:0x1044ef5b0 result=NOT_RECOVERED]
//
//   The original note, kept because its warning is still correct:
//   {0x5c0, 0x5c8, 0x5d8} are all `[…]` initialised from the same empty-array singleton, so nothing
//   at the init distinguishes them, and neither the export trie nor the field records order the
//   globals. Do NOT guess the three from field order.
// ⚑[tool=bind_oracle ref=__got:0x104112d10 result=__swiftEmptySetSingleton]
// ⚑[tool=field_offset_vector ref=MetalSubtitleView:0x1044230b8 result=offsets-0x8-0x30-0x38-0x40-0x48-0x50-0x58]
class MetalSubtitleView: MTKView {
    public var metalDrawable: (any MetalDrawable)? // §8.6 — offset global 0x1044ef5a8 (vpWvd)
    public var dynamicRange: DynamicRange = .sdr // ⚑ default inferred → M2; offset global 0x1044ef5b8 (vpWvd)
    private var cancellables: Set<AnyCancellable> = [] // offset global 0x1044ef5d0 (empty-set singleton)
    private var subtitleImages: [SubtitleImageInfo] = [] // offset global 0x1044ef5c0 -> field offset 0x40
    private var pendingTexts: [SubtitleTextInfo] = [] // offset global 0x1044ef5c8 -> field offset 0x48
    private var parts: [SubtitlePart] = [] // offset global 0x1044ef5d8 -> field offset 0x50
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
