//
//  PointerImagePipeline.swift
//  KSPlayer
//
//  STOOD UP in session 116 from Forward 1.3.17. Forward-only: neither this class nor the
//  `ImagePipelineType` protocol it conforms to appears anywhere in upstream KSPlayer.
//
//  ⚑ FILE PLACEMENT IS A CHOICE, NOT A READING. The class materialises no `#fileID`, no
//    `#function`, no `#line` and no string literal at all — the ONLY `adrp` in its whole 0x3ec-byte
//    __text extent (0x101aa4434-0x101aa4820) is the `__got` load for `kCFAllocatorDefault`, and
//    `file_placement_sweep` returns zero rows for it. So the declaring FILE and the source ORDER of
//    its members are not recoverable. It is filed beside `PixelBufferProtocol.swift` because
//    `PixelBuffer.cgImage()` @0x101a8ada4 calls this class's `cgImage()` directly; that is
//    proximity, not evidence.
//  ⚑[tool=file_placement_sweep ref=PointerImagePipeline result=0-rows-no-fileID-literal]
//
//  Class shape: root class (SuperclassType rel-ptr 0), `metadata_init=0`, descriptor 0x1039f1a1c,
//  metadata 0x1044ee950, accessor 0x101aa4824. Field-offset vector @0x1044ee9a0, InstanceSize 0x34,
//  AlignMask 7. All five stored properties are `let` — every field record has the IsVar bit clear.
//  ⚑[tool=field_offset_vector ref=PointerImagePipeline result=5-let-fields-InstanceSize-0x34]
//
//  🚧 THE CONFORMANCE IS DELIBERATELY NOT DECLARED. The binary says this class conforms to
//    `KSPlayer.ImagePipelineType` (conformance descriptor 0x10356cd70, protocol descriptor
//    0x1039f15dc, 4 requirements: Init, Init, Method, Method). Writing that conformance is
//    IMPOSSIBLE without inventing, and four independent routes were run to establish it:
//      1. the requirement records carry NO name field — each is 8 bytes {Flags, DefaultImplementation}
//         and all four DefaultImplementation pointers are NULL, so there is no default body to name;
//      2. ZERO of the 57,138 export-trie symbols contain "ImagePipelineType" — no `Tj` dispatch
//         thunk, no `Tq` descriptor, no requirements-base, no witness-table symbol;
//      3. BOTH witness tables for the protocol (this class's 0x1041da730 and the other conformer's
//         0x1041da250) have all four witnesses set to `_swift_deletedMethodError`;
//      4. the only other conformer is `Accelerate.vImage.PixelBuffer`, outside KSPlayer entirely.
//    The kind vector {Init, Init, Method, Method} is the only recoverable fact, and while this class
//    does expose exactly two inits and two instance methods, NOTHING in the binary maps requirement
//    index to member. Declaring the protocol would mean inventing four names AND four signatures,
//    and signatures are outside what the name-exhaustion route can license.
//  ⚑[tool=protocol_signature ref=ImagePipelineType:0x1039f15dc result=4-requirements-no-names-no-signatures]
//  ⚑[tool=decode_witness_table ref=0x1041da730 result=4x-swift_deletedMethodError]
//
//  ⚑ ACCESS LEVEL IS NOT DECIDABLE for any member or field: the class's entire trie footprint is 14
//    symbols (cgImage, deallocate, both allocating inits + their two `Tq` descriptors, both inits,
//    Ma/Mm/Mn/N/fD/fd) and not one carries a `33_<hex>LL` private discriminator, so private and
//    fileprivate are RULED OUT — but there is no `vpMV`, no `vpfi` and no accessor symbol for any
//    field, so internal-vs-public is unreadable. Written `internal` as the narrower claim.
//  ⚑ `cgImage()` and `deallocate()` are NON-OVERRIDABLE: neither has a vtable slot nor a `Tq`
//    method descriptor, while both allocating inits have both. So the source spells either the CLASS
//    `final` or the two METHODS `final`. Which of the two is not decidable; the class is written
//    `final` as the form that produces the observed vtable (3 Init slots and nothing else).
//  ⚑ No `deinit` is written: the binary's is `mov x0,x20 / ret` at a 100-way ICF fold — a pure-ARC
//    teardown the compiler synthesises, so writing one would be an addition.
//
//  🚧 vtable slot[2] is a THIRD `Init` with `Impl = NULL` against exactly two init symbols in the
//    trie. On a non-final class a NULL Impl reads as dead-stripped rather than absent, so a third
//    designated initialiser plausibly exists in Forward and is unnameable. Not invented.
//
import CoreGraphics
import Foundation

final class PointerImagePipeline {
    let rgbData: UnsafeMutablePointer<UInt8>
    let bytesPerRow: Int
    let width: Int
    let height: Int
    let alphaInfo: CGImageAlphaInfo

    /// @0x101aa4578, 5 instructions — a pure field-store body, read in full:
    /// `stp x0,x1,[self,#0x10]` / `stp x2,x3,[self,#0x20]` / `str w4,[self,#0x30]` / return self.
    /// ⚠️ The LABEL is `stride` but the field is `bytesPerRow`, and here the value goes in
    ///   UNCHANGED — contrast the palette init below, where `stride` is a PIXEL count and
    ///   `bytesPerRow` is `stride * 4`. The same label means two different things in the two inits;
    ///   that is Forward's, not a transcription slip.
    init(rgbData: UnsafeMutablePointer<UInt8>, stride: Int, width: Int, height: Int, alphaInfo: CGImageAlphaInfo) {
        self.rgbData = rgbData
        bytesPerRow = stride
        self.width = width
        self.height = height
        self.alphaInfo = alphaInfo
    }

    /// @0x101aa448c, 59 instructions, read in full. Six external callees, every one named through
    /// its stub's `__got` slot: `CFDataCreate`, `CGDataProviderCreateWithCFData`,
    /// `CGColorSpaceCreateDeviceRGB`, `CGImageCreate`, and three `objc_release`.
    ///
    /// `bitsPerPixel` is `alphaInfo == 0 ? 24 : 32`, and raw 0 is `kCGImageAlphaNone` — so 24 exactly
    /// when there is no alpha channel, 32 otherwise. The CFData length is `bytesPerRow * height`
    /// under the body's ONE overflow trap, i.e. a checked multiply.
    ///
    /// `CGImageCreate` is called with all 11 arguments, x0-x7 plus three on the stack, in this order:
    /// width, height, bitsPerComponent = 8, bitsPerPixel, bytesPerRow, space, bitmapInfo = the raw
    /// `alphaInfo` zero-extended, provider, decode = NULL, shouldInterpolate = false, intent = 0.
    ///
    /// ⚠️ The two nil-bail paths DIFFER and the difference is the ownership: the `CFDataCreate`-nil
    ///   path returns nil releasing NOTHING, while the `CGDataProviderCreateWithCFData`-nil path
    ///   releases the CFData first. On success all three CF objects are released and the CGImage is
    ///   returned WITHOUT a release, i.e. at +1.
    /// ⚑[tool=bind_oracle ref=CGImageCreate:0x104108ed8 result=CoreGraphics-_CGImageCreate]
    func cgImage() -> CGImage? {
        let length = bytesPerRow * height
        guard let data = CFDataCreate(kCFAllocatorDefault, rgbData, length) else {
            return nil
        }
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }
        let space = CGColorSpaceCreateDeviceRGB()
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: alphaInfo == .none ? 24 : 32,
                       bytesPerRow: bytesPerRow,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// @0x101aa46d4, 76 instructions, read statement by statement. The allocating entry
    /// @0x101aa458c is NOT a thunk — it inlines this whole body after `swift_allocObject(_, 0x34, 7)`,
    /// which is a second independent read of the same statements and agrees instruction for
    /// instruction on every part checked.
    ///
    /// Order is the binary's: width/height are stored FIRST (`stp x0,x1,[self,#0x20]`), then
    /// `bytesPerRow = stride * 4` behind a ±2^61 range guard, then the buffer.
    ///
    /// The allocation is `swift_slowAlloc(byteCount: (stride * height) * 4, alignMask: -1)` with the
    /// `stride * height` product and the `* 4` separately overflow-checked, followed by a `bzero`
    /// over the same byte count that is SKIPPED when the element count is zero.
    /// ⚑ The Swift SPELLING of the allocate-and-zero pair is not decidable — several spellings lower
    ///   to `swift_slowAlloc` + `bzero`. Written as the plainest pair that produces it.
    ///
    /// The loop is a plain nested row/column scan, outer over `height` and inner over `width`, with
    /// a row base advanced by `stride` (NOT by width) under a checked add. The per-pixel statement is
    /// exactly `dst[i] = palette[Int(bitmap[i])]` with ONE shared index `i = rowBase + x`: the source
    /// is byte-indexed (`ldrb w12,[bitmap,x11]`) and the destination UInt32-indexed
    /// (`str w12,[dst,x11,lsl #2]`).
    ///
    /// `alphaInfo` is stored as the constant 4. That 4 is `.first` (ARGB), corroborated independently
    /// by `PixelBuffer.cgImage()`, whose RGB24 / RGBA / ARGB cases store 0 / 3 / 4 into this very
    /// field — matching `.none` / `.last` / `.first`.
    /// ⚑[tool=export_trie_oracle ref=PointerImagePipeline.init(width:height:stride:bitmap:palette:):0x101aa46d4 result=one-symbol-no-fold]
    init(width: Int, height: Int, stride: Int, bitmap: UnsafeMutablePointer<UInt8>, palette: UnsafePointer<UInt32>) {
        self.width = width
        self.height = height
        bytesPerRow = stride * 4
        let count = stride * height
        let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        var y = 0
        var rowBase = 0
        if height > 0 {
            repeat {
                var x = 0
                while x < width {
                    let i = rowBase + x
                    buffer[i] = palette[Int(bitmap[i])]
                    x += 1
                }
                rowBase += stride
                y += 1
            } while y < height
        }
        rgbData = UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: UInt8.self)
        alphaInfo = .first
    }

    /// @0x101aa4804, 4 instructions: load `rgbData` and tail-call
    /// `swift_slowDealloc(ptr, -1, -1)`. It touches no other field.
    /// ⚑[tool=bind_oracle ref=swift_slowDealloc:0x104113070 result=libswiftCore-_swift_slowDealloc]
    @used func deallocate() {
        rgbData.deallocate()
    }
}
