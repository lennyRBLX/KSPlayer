//
//  CustomProgressView.swift
//  KSPlayer
//
//  Reconstructed from Forward-TF 1.3.17. Class descriptor 0x1039f3a94.
//
#if canImport(UIKit) && canImport(CallKit)
import UIKit

// Superclass read from the class descriptor's SuperclassType field at desc+0x14, which holds the
// relative pointer 0x0023a334 -> 0x103c2dddc, whose mangled bytes are `So6UIViewC` = ObjC UIView.
// ⚑[tool=export_trie_oracle ref=CustomProgressView:0x1039f3a94 result=NO_ORPHAN_SUBTREE]
// The class exports NOTHING: `export_trie_oracle --class CustomProgressView` returns "no orphan
// subtree found", so every member name below is unrecovered, not merely unread.
class CustomProgressView: UIView {
    // Field records, in reflection order, from FieldDescriptor 0x103cbf188 (NumFields=4). Types are
    // the resolved binary types, not inferred from use.
    // ⚑[tool=dump_binary_field_types ref=CustomProgressView:0x1039f3a94 result=4-fields-resolved]
    //
    // The four direct field-offset globals are an unexported contiguous run at
    // 0x1044f1050..0x1044f1068 (stride 8, static values 8/16/24/32), bounded on the left by the
    // pointer-valued global at 0x1044f1048. Entry i is field record i. These are PRE-metadata-init
    // static values and are global identities, NOT runtime byte offsets.
    // ⚑[tool=fieldrec ref=CustomProgressView:0x1039f3a94 result=NumFields-4]
    let playView: IOSVideoPlayerView          // record 0, flags=0, offset-global 0x1044f1050
    var progressSlider: KSSlider              // record 1, flags=2, offset-global 0x1044f1058
    var currentTimeLabel: UILabel             // record 2, flags=2, offset-global 0x1044f1060
    var totalTimeLabel: UILabel               // record 3, flags=2, offset-global 0x1044f1068

    // Designated init, body @0x101b13374 (288 B / 72 instr), read end to end. It is NOT in the
    // vtable's Init slot (idx9 carries Impl=NULL) and `locate_class_init` found 0 construction
    // sites; it was reached instead from the metadata accessor's xrefs, which is the check that
    // tool names when it returns 0.
    // ⚑[tool=locate_class_init ref=CustomProgressView:0x1039f3a94 result=0-construction-sites]
    // ⚑[invented=init(playView:frame:) addr=0x101b13374 exhaustion=name_exhaustion_gate approved=user-blanket-s115]
    //
    // ⚠️ PARAMETER ORDER IS NOT DETERMINED BY THE BINARY. `playView` arrives in x0 and the CGRect
    // in v0-v3 (saved to v11/v10/v9/v8 across the field stores at 0x101b13394-0x101b133a0). Swift
    // allocates integer and floating-point parameters from separate register banks, so the
    // register assignment is identical under either declaration order. The labels are read; their
    // ORDER is a choice, and it is flagged rather than asserted.
    init(playView: IOSVideoPlayerView, frame: CGRect) {
        // str x0, [x20, offset-global 0x1044f1050] @0x101b133b0 — entry0, confirming the mapping.
        self.playView = playView
        // The three subviews are read off playView.toolBar, not constructed. Both the intermediate
        // and the three fields were named from their vpWvd symbols after BOTH offset resolvers
        // refused ("NOT RECOVERED — do not guess it") for IOSVideoPlayerView and VideoPlayerView.
        // ⚑[tool=export_trie_oracle ref=PlayerView.toolBar:0x1044e7508 result=vpWvd-named]
        // ⚑[tool=export_trie_oracle ref=PlayerToolBar.timeSlider:0x1044e7460 result=vpWvd-named]
        // ⚑[tool=export_trie_oracle ref=PlayerToolBar.currentTimeLabel:0x1044e7448 result=vpWvd-named]
        // ⚑[tool=export_trie_oracle ref=PlayerToolBar.totalTimeLabel:0x1044e7450 result=vpWvd-named]
        let toolBar = playView.toolBar
        progressSlider = toolBar.timeSlider
        currentTimeLabel = toolBar.currentTimeLabel
        totalTimeLabel = toolBar.totalTimeLabel
        super.init(frame: frame)   // objc_msgSendSuper2 @0x101b13454, v0-v3 restored from v11-v8
        setupUI()                  // bl 0x101b134a0 @0x101b13464 — the sole call site of setupUI
    }

    // COMPILER-FORCED, NOT READ FROM THE BINARY. UIView declares `required init?(coder:)`, so any
    // subclass declaring a designated init must restate it. vtable idx11 is a Method with
    // Impl=NULL and was NOT read; this stub is what the language demands, not a reconstruction.
    // ⚑[tool=vtable_impl_oracle ref=CustomProgressView:idx11 result=Impl-NULL-unread]
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // ⚑[invented=setupUI addr=0x101b134a0 exhaustion=name_exhaustion_gate approved=user-blanket-s115]
    // vtable idx10 / slot24 (VTableOffset=14), flags=0x0010 Method, Impl == body (no branch thunk).
    // Extent 0x101b134a0-0x101b13ac8, 1576 B / 394 instr.
    //
    // The NAME is invented. Every recovery route was run and every one failed:
    //   export trie at the body ....... NOT IN TRIE (a real negative)
    //   vtable Impl ................... equal to the body, so there is no thunk to name instead
    //   #function / #file literal ..... none present
    //   objc selector sent / IMP ...... not an IMP in any of 220 classes' method lists
    //   unique string literal ......... 0 literals
    // ⚑[tool=name_exhaustion_gate ref=CustomProgressView.setupUI:0x101b134a0 result=EXHAUSTED]
    //
    // The gate's DEFAULT verdict is INLINE-INSTEAD, because the body has exactly one call site
    // image-wide (0x101b13464, inside the 72-instruction FUN_101b13374). That heuristic is refused
    // here on structural grounds, not for convenience: this address occupies a vtable slot as a
    // `Method`, and the compiler only emits a vtable slot for a declared, overridable member. A
    // one-site inline expression never gets one. Hence --allow-single-site.
    func setupUI() {
        backgroundColor = .clear

        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.minimumTrackTintColor = .white
        progressSlider.maximumTrackTintColor = .gray
        // UIGraphicsImageRenderer(size:) with d0=d1=1.0 at 0x101b13578/0x101b1357c, then
        // imageWithActions: over a heap block allocated by _swift_allocObject(32, 7).
        let thumbImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        progressSlider.setThumbImage(thumbImage, for: .normal)       // x3 = 0
        progressSlider.setThumbImage(thumbImage, for: .highlighted)  // x3 = 1
        progressSlider.setThumbImage(thumbImage, for: .selected)     // x3 = 4
        progressSlider.setMinimumTrackImage(nil, for: .normal)       // x2 = 0, x3 = 0
        progressSlider.setMaximumTrackImage(nil, for: .normal)       // x2 = 0, x3 = 0

        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        totalTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        // ofSize: is the immediate 14.0 at 0x101b136ec; the weight is loaded indirectly through the
        // __got slot 0x10410b018, so it is read as a bound symbol rather than an inline constant.
        // ⚑[tool=body_fingerprint ref=CustomProgressView.setupUI:0x101b136e0 result=got-0x10410b018]
        let font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        currentTimeLabel.font = font
        totalTimeLabel.font = font
        currentTimeLabel.textColor = .white
        totalTimeLabel.textColor = .white

        addSubview(progressSlider)
        addSubview(currentTimeLabel)
        addSubview(totalTimeLabel)

        // Eight constraints, stored into the array buffer at [x24, #0x20 ... #0x58]
        // (_swift_allocObject(96, 7) at 0x101b137f0), then bridged to NSArray and passed to
        // +[NSLayoutConstraint activateConstraints:] at 0x101b13a8c.
        NSLayoutConstraint.activate([
            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 12),
            progressSlider.trailingAnchor.constraint(equalTo: totalTimeLabel.leadingAnchor, constant: -12),
            progressSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressSlider.heightAnchor.constraint(equalToConstant: 30),
            currentTimeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            currentTimeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            totalTimeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            totalTimeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
#endif
