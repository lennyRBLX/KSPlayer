import Foundation
import Metal
import QuartzCore

// Forward-only protocol, `$s8KSPlayer8DrawableMp` @0x1039eda20. It exists to type
// `MetalPlayView.drawable`, whose field record is a NON-optional existential (`_p`, no `Sg`) and
// whose accessors the trie names `KSPlayer.MetalPlayView.drawable.getter/setter/modify :
// KSPlayer.Drawable`.
//
// protocol_signature: 2 requirements, BOTH instance Methods; NumRequirementsInSignature 0, so it
// is NOT class-constrained and must not be written `: AnyObject`; no associated types.
//
// Declared EMPTY with its requirements pinned, on the same footing as `MovieStream` and
// `VideoPipeline`. The two requirement names are NOT recoverable:
//   · conformance_walker gives three conformers — __C.CAMetalLayer (wt 0x1041d9e70) and two
//     RealityKit types whose conformer descriptors lie outside the image (0x1052f5900,
//     0x1052f5700), so decode_witness_table cannot walk them at all.
//   · CAMetalLayer's own two witnesses are 0x101a856dc, which forwards to the trie-negative
//     0x101a854b0, and 0x101a856fc, whose only distinguishing act is an ObjC `setEDRMetadata:`
//     send — a selector, not a Swift requirement name.
//
// A NEAR MISS WORTH RECORDING, because it would be easy to take as evidence: the trie contains
// `(extension in KSPlayer):RealityKit.TextureResource.Drawable.present(commandBuffer:)`. That
// `Drawable` is RealityKit's own NESTED TextureResource.Drawable, a different type that merely
// shares the name — it is not a requirement of this protocol, and reading it as one would put a
// fabricated method here.
// ⚑[tool=conformance_walker ref=KSPlayer.Drawable:0x1039eda20 result=requirement-names-irreducible]
public protocol Drawable {
    // 2 instance Method requirements IRREDUCIBLE — see above.
}

// The only conformer whose witness table is walkable in this image. The other two are RealityKit
// types (TextureResource and TextureResource.DrawableQueue) whose conformances the binary records
// but whose descriptors are out of image, so they are not declared here.
extension CAMetalLayer: Drawable {}

// FlickerDetector — a small value type absent from Sources/ entirely, recovered because
// MetalPlayView stores one (field 15). Nominal type descriptor 0x1039efdcc, NumFields=3, read
// straight from the reflection field records:
//   lastSignature : Swift.Int?   (`SiSg`, var)
//   changeCount   : Swift.Int    (`Si`,   var)
//   notified      : Swift.Bool   (`Sb`,   var)
// No method of this type is named anywhere in the trie, so only its SHAPE is declared here; what
// it does with those three fields is not read.
// ⚑[tool=fieldrec ref=KSPlayer.FlickerDetector:0x1039efdcc result=3-fields-no-named-methods]
public struct FlickerDetector {
    public var lastSignature: Int?
    public var changeCount: Int
    public var notified: Bool

    public init(lastSignature: Int? = nil, changeCount: Int = 0, notified: Bool = false) {
        self.lastSignature = lastSignature
        self.changeCount = changeCount
        self.notified = notified
    }
}
