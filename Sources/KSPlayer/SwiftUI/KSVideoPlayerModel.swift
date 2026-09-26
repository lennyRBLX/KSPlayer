//
//  KSVideoPlayerModel.swift
//  KSPlayer
//
//  Reconstructed from Forward-TF 1.3.17. Class descriptor 0x1039f24cc.
//
import Combine
import Foundation

// Root class: SuperclassType @ desc+0x14 reads 0, which is the "no superclass" encoding.
// ⚑[tool=fieldrec ref=KSVideoPlayerModel:0x1039f24cc result=NumFields-8]
//
// Unlike CustomProgressView, this class is richly named: the orphaned export trie carries 73
// symbols for it, so every member below is READ, not invented.
// ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel:0x1039f24cc result=73-symbols]
//
// `@MainActor` is DERIVED, not stylistic. The binary calls `KSVideoPlayer.Coordinator.init()`
// (0x101acc684) and reads `Coordinator.playerLayer` synchronously from next()/previous(); that
// Coordinator is declared `@MainActor public final class` at KSVideoPlayer.swift:73-74, and Swift
// permits a synchronous call into MainActor-isolated state only from a MainActor-isolated caller.
// The isolation is therefore forced by the call graph the binary already contains.
@MainActor
public class KSVideoPlayerModel: ObservableObject {
    // Nested enum, descriptor 0x1039f266c, FieldDescriptor 0x103cbe88c, NumFields=3, all three
    // records carrying an EMPTY mangled type — i.e. three payload-free cases, in this order.
    // The `O` in `...AC09FocusableF0OSgvpfP` is what identifies it as an enum rather than a class.
    // ⚑[tool=fieldrec ref=KSVideoPlayerModel.FocusableView:0x1039f266c result=3-empty-cases]
    enum FocusableView {
        case play
        case controller
        case slider
    }

    // NULL-flag alignment (l2-block-deferral-vs-spelling #5). The field RECORD carries only the
    // descriptor's short name `Coordinator`, while the offset global 0x104c63810 and the getter
    // 0x101acb1f8 BOTH demangle to `KSPlayer.KSVideoPlayer.Coordinator`. Bare `Coordinator` does
    // not resolve here (the type is nested in KSVideoPlayer), so this alias aligns the source text
    // with the record. A typealias is erased and leaves NO binary artifact, so which spelling the
    // original source used is UNDECIDABLE from the image — recorded, not presented as recovered.
    // ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel.config:0x104c63810 result=qualified-in-vpWvd]
    public typealias Coordinator = KSVideoPlayer.Coordinator

    // Field-record order is the declaration order below; it is the binary's, not a preference.
    // Access per field is read from the trie: a property descriptor (vpMV/vpZMV) is public-
    // exclusive; a `33_<hash>LL` discriminator is private; neither means internal.
    // Declaration defaults are read from the vpfi bodies, not assumed.
    // ⚑[tool=vpfi_initializer_oracle ref=KSVideoPlayerModel result=5-defaults-4-distinct-bodies]
    @Published public var title: String                                    // rec0 `_title`
    public var config: Coordinator                                      // rec1, NON-optional
    public var options: KSOptions                                          // rec2
    public var urls: [URL] = []                                            // rec3, __swiftEmptyArrayStorage
    @Published public var url: URL?                                        // rec4, vpfi = Optional.none
    @Published var focusableView: KSVideoPlayerModel.FocusableView?                           // rec5, internal, vpfi = 0
    @Published var showVideoSetting: Bool = false                          // rec6, internal, vpfi = 0
    private var cancellables: Set<AnyCancellable> = []                     // rec7, __swiftEmptySetSingleton

    public convenience init(playerLayer: KSPlayerLayer) {
        self.init(
            title: playerLayer.url.lastPathComponent,
            config: KSVideoPlayer.Coordinator(playerLayer: playerLayer),
            options: playerLayer.options,
            url: .some(playerLayer.url)
        )
    }

    // `config` is NON-optional in the field record (offset global 0x104c63810 demangles to
    // `... .config : KSPlayer.KSVideoPlayer.Coordinator`, no `Sg`) even though the init PARAMETER
    // is optional. The init supplies a fresh Coordinator when the argument is nil — the
    // `Coordinator.init()` call at 0x101acc684, guarded by the metadata accessor at 0x101acc670.
    // Signature is read whole from the trie, not inferred:
    // ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel.__allocating_init:0x101aca9c8 result=4-param-signature]
    //
    // ⚠️ THIS BODY IS PINNED AND INCOMPLETE — DO NOT READ IT AS A FINISHED RECONSTRUCTION.
    // The real init is at 0x101acc3a8 (allocating thunk 0x101aca9c8 tail-calls it at 0x101acaa18),
    // 1324 B / 331 instr. The four parameter assignments below are evidenced by the three named
    // field-offset stores plus the read signature. The TAIL IS NOT WRITTEN: the body continues
    // with five `Published(initialValue:)` constructions, a read of
    // `Coordinator.objectWillChange` (0x101acc74c), a `swift_weakInit` capture (0x101acc780), a
    // `Publisher.sink(receiveValue:)` (0x101acc7b4) whose AnyCancellable is `store(in:)`-ed into
    // `cancellables` (0x101acc7e4), and an assignment to
    // `Coordinator.onURLChanged : ((KSPlayerLayer, URL) -> ())?` (offset global 0x104c63568).
    // Those closures were NOT read instruction-by-instruction and are therefore not written.
    // ⚑[tool=body_fingerprint ref=KSVideoPlayerModel.init:0x101acc3a8 result=pinned-subscription-tail]
    public init(title: String, config: KSVideoPlayer.Coordinator?, options: KSOptions, url: URL?) {
        self.title = title
        self.config = config ?? KSVideoPlayer.Coordinator()
        self.options = options
        self.url = url
    }

    // vtable idx37 / slot55 (VTableOffset=18), Impl=0x101acccfc, 180 B / 45 instr. Read end to end.
    // Name is READ from the trie: `$s8KSPlayer18KSVideoPlayerModelC4nextyyF`.
    //
    // Access is declared internal (no modifier): the mangled name carries no `33_<hash>LL`
    // discriminator, so it is not private, and vtable membership rules out `final` — but nothing
    // in the binary separates internal from public for a method, so the weaker claim is written.
    // ⚑[tool=vtable_impl_oracle ref=KSVideoPlayerModel:idx37 result=slot55-Impl-0x101acccfc]
    //
    // The dispatch is virtual, through metadata byte-offset 0x3e0 = slot 124 = KSComplexPlayerLayer
    // idx12, whose Impl 0x1019d27a8 the trie names `playNextURL()`.
    // ⚑[tool=export_trie_oracle ref=KSComplexPlayerLayer.playNextURL:0x1019d27a8 result=named]
    @used func next() {
        if let layer = config.playerLayer as? KSComplexPlayerLayer {
            layer.playNextURL()
        }
    }

    // vtable idx38 / slot56, Impl=0x101accdb0, 148 B / 37 instr. Read end to end. Structurally
    // identical to next() except the call is DIRECT to 0x1019d3518 rather than virtual — that
    // address is in no vtable, which is what makes `playPreviousURL()` internal rather than public.
    // That target already carries its own invented-name marker at KSPlayerLayer.swift:1342, landed
    // by an earlier session and reasoned from this exact next/previous pairing.
    // ⚑[tool=export_trie_oracle ref=KSVideoPlayerModel.previous:0x101accdb0 result=named]
    @used func previous() {
        if let layer = config.playerLayer as? KSComplexPlayerLayer {
            layer.playPreviousURL()
        }
    }
}
