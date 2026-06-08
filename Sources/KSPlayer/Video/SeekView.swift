//
//  SeekView.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2018/11/14.
//
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
public protocol SeekViewProtocol {
    func set(text: String, isAdd: Bool)
}

/// RE: 0x1014F18CC (KSPlayer.SeekView metadata accessor, 1.3.15)
/// ObjC-rooted UIView seek-direction indicator (§5.5 / §18.21). Black 0.7-alpha
/// rounded rect with a `forward.fill` icon and a time label; hidden by default.
class SeekView: UIView {
    private let seekToViewImage = UIImageView()
    private let seekToLabel = UILabel()
    /// RE: 0x1014F10D4 (SeekView_init_setup, 1.3.15)
    override public init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(seekToViewImage)
        addSubview(seekToLabel)
        seekToLabel.font = .systemFont(ofSize: 13)
        seekToLabel.textColor = UIColor(red: 0.9098, green: 0.9098, blue: 0.9098, alpha: 1.0)
        // §18.21: decompile of 0x1014F10D4 uses the grayscale `white:alpha:` initializer
        // (alpha 0x3FE6666666666666 = 0.7), not red:green:blue:alpha:. Behaviorally black @ 0.7.
        backgroundColor = UIColor(white: 0, alpha: 0.7)
        cornerRadius = 4
        clipsToBounds = true
        isHidden = true
        // The decompile of 0x1014F10D4 assigns `forward.fill` unconditionally (the SF symbol is
        // assumed available at the binary's deployment target). The explicit multi-platform clause
        // states the real requirement — forward.fill needs iOS 13 / tvOS 13 / macOS 11 — instead of
        // a bare `macOS 11.0, *` that reads as macOS-only (its `*` is always-true on UIKit anyway).
        if #available(iOS 13.0, tvOS 13.0, macOS 11.0, *) {
            seekToViewImage.image = UIImage(systemName: "forward.fill")
        }
        translatesAutoresizingMaskIntoConstraints = false
        seekToViewImage.translatesAutoresizingMaskIntoConstraints = false
        seekToLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            seekToViewImage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            seekToViewImage.centerYAnchor.constraint(equalTo: centerYAnchor),
            seekToViewImage.widthAnchor.constraint(equalToConstant: 25),
            seekToViewImage.heightAnchor.constraint(equalToConstant: 15),
            seekToLabel.leadingAnchor.constraint(equalTo: seekToViewImage.trailingAnchor, constant: 10),
            seekToLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if canImport(AppKit)
    var backgroundColor: UIColor? {
        get {
            if let layer, let cgColor = layer.backgroundColor {
                return UIColor(cgColor: cgColor)
            } else {
                return nil
            }
        }
        set {
            backingLayer?.backgroundColor = newValue?.cgColor
        }
    }
    #endif
}

extension SeekView: SeekViewProtocol {
    /// RE: 0x1014F18CC (KSPlayer.SeekView, set(text:isAdd:), 1.3.15)
    /// Per §5.5, the `forward.fill` icon is rotated 180° when seeking backward
    /// (`isAdd == false`) so it reads as a rewind glyph; forward seeks keep it at 0°.
    public func set(text: String, isAdd: Bool) {
        seekToLabel.text = text
        // §5.5 / §18.21 document only the rotation: `centerRotate` (UIKitExtend.swift:218 /
        // AppKitExtend.swift:141) sets its own anchorPoint (0.5,0.5) + transform, so the
        // single call below fully satisfies the spec. No pre-rotation layer fix-up exists in
        // the decompile of 0x1014F18CC.
        seekToViewImage.centerRotate(byDegrees: isAdd ? 0.0 : 180)
    }
}
