//
//  CustomDrawingLabel.swift
//  KSPlayer
//
//  Forward addition (RE): a custom-drawing outlined-text label rooted on
//  UIView (NOT UILabel — confirmed by types.json parent: __C.UIView). It
//  renders model-driven text with a shadow pass, an optional border/stroke
//  pass, and a fill pass — the classic stroke-then-fill outlined-subtitle
//  renderer. Style is supplied by the shared `CustomTextModel` value type,
//  which is also driven by the SwiftUI `CustomTextDrawingView` wrapper.
//
//  Binary: _TtC8KSPlayer18CustomDrawingLabel (8 functions)
//  RE source: Forward v1.3.15
//

import CoreGraphics
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - CustomTextModel

/// Style model shared by the SwiftUI `CustomTextDrawingView` and the UIKit/AppKit
/// `CustomDrawingLabel`.
///
/// RE: `CustomTextModel` — types.json top-level KSPlayer struct (parent: None),
/// 8 fields in the exact binary order below. The cross-platform `UIFont`/`UIColor`
/// typealiases (NSFont/NSColor on macOS) come from `AppKitExtend.swift`, so the
/// binary's `__C.UIFont`/`__C.UIColor` field types map 1:1 on every target.
public struct CustomTextModel {
    /// #1 — the string to render.
    public var text: String
    /// #2 — text font (`__C.UIFont`).
    public var font: UIFont
    /// #3 — fill color for the text (`__C.UIColor`).
    public var textColor: UIColor
    /// #4 — border/stroke color for the outline pass (`__C.UIColor`).
    public var borderColor: UIColor
    /// #5 — shadow color for the shadow pass (`__C.UIColor`).
    public var shadowColor: UIColor
    /// #6 — border/stroke width; the stroke pass runs only when this is > 0.
    public var borderWidth: CGFloat
    /// #7 — shadow offset (applied symmetrically as the CGSize width/height).
    public var shadowOffset: CGFloat
    /// #8 — shadow blur radius.
    public var shadowRadius: CGFloat

    public init(
        text: String = "",
        font: UIFont = .systemFont(ofSize: 16),
        textColor: UIColor = .white,
        borderColor: UIColor = .black,
        shadowColor: UIColor = .black,
        borderWidth: CGFloat = 0,
        shadowOffset: CGFloat = 0,
        shadowRadius: CGFloat = 0
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.borderColor = borderColor
        self.shadowColor = shadowColor
        self.borderWidth = borderWidth
        self.shadowOffset = shadowOffset
        self.shadowRadius = shadowRadius
    }
}

// MARK: - CustomTextDrawingView (SwiftUI bridge)

/// SwiftUI wrapper that bridges to the UIKit/AppKit `CustomDrawingLabel` for the
/// actual pixel drawing.
///
/// RE: `CustomTextDrawingView` — types.json SwiftUI struct (parent: None) with a
/// single field `model :: KSPlayer.CustomTextModel`. No named function body in
/// this revision (value-witness only); the drawing is delegated to the label.
public struct CustomTextDrawingView: UIViewRepresentable {
    public var model: CustomTextModel

    public init(model: CustomTextModel) {
        self.model = model
    }

    #if canImport(UIKit)
    public func makeUIView(context: Context) -> CustomDrawingLabel {
        let label = CustomDrawingLabel()
        label.model = model
        return label
    }

    public func updateUIView(_ uiView: CustomDrawingLabel, context: Context) {
        uiView.model = model
    }
    #else
    public func makeNSView(context: Context) -> CustomDrawingLabel {
        let label = CustomDrawingLabel()
        label.model = model
        return label
    }

    public func updateNSView(_ nsView: CustomDrawingLabel, context: Context) {
        nsView.model = model
    }
    #endif
}

// MARK: - CustomDrawingLabel

/// Outlined-text label rooted on UIView (NSView on macOS). The text, fonts,
/// colors, border, and shadow all come from the optional `model`; when the model
/// is `nil` the view defers to its superclass draw (a blank/cleared view).
///
/// The platform split below uses the same `#if canImport(UIKit)` / `#else`
/// pattern as `PaddedLabel` in MetalSubtitleView.swift: `draw(_:)` is the shared
/// custom-drawing entry point on both UIKit (`UIView.draw(_:)`) and AppKit
/// (`NSView.draw(_:)`), and the cross-platform `UIView`/`UIColor`/`UIFont`
/// typealiases keep the body identical across targets.
public class CustomDrawingLabel: UIView {
    // MARK: Model

    /// Style model. Optional — `draw(_:)` dispatches on `model == nil`, so the
    /// optionality is load-bearing (matches types.json `model :: CustomTextModel?`).
    ///
    /// RE: getter `CustomDrawingLabel_model_getter` @ 0x1000BCD18,
    ///     setter `CustomDrawingLabel_model_setter` @ 0x1000AED28.
    public var model: CustomTextModel? {
        didSet { setModelNeedsDisplay() }
    }

    /// RE: `CustomDrawingLabel_setModel` @ 0x1001C6D78 — the model-mutation
    /// observation hook. The stored-property `didSet` routes here to invalidate
    /// the view so a model change repaints the outlined text.
    private func setModelNeedsDisplay() {
        #if canImport(UIKit)
        setNeedsDisplay()
        #else
        needsDisplay = true
        #endif
    }

    // MARK: Init

    /// RE: `CustomDrawingLabel_convenienceInit` @ 0x10149D490
    public convenience init() {
        self.init(frame: .zero)
    }

    #if canImport(UIKit)
    /// RE: `CustomDrawingLabel_initWithFrame` @ 0x10149D634 — designated init.
    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    /// RE: `CustomDrawingLabel_initWithCoder` @ 0x10149D880 — coder init.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }
    #else
    /// RE: `CustomDrawingLabel_initWithFrame` @ 0x10149D634 — designated init.
    /// AppKit mirror: NSView is layer-backed and non-opaque for the clear
    /// background the UIKit path sets via `backgroundColor`/`isOpaque`.
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// RE: `CustomDrawingLabel_initWithCoder` @ 0x10149D880 — coder init.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Use top-left origin so the attributed-string draw rect matches the UIKit
    /// coordinate space (UIView is already top-left origin).
    override public var isFlipped: Bool { true }
    #endif

    // MARK: Draw

    /// RE: `CustomDrawingLabel_drawRect` @ 0x10149DA28 — override of UIView's
    /// `draw(_:)` (`drawRect:`).
    ///
    /// Behavior (verified via decompile of 0x10149DA28):
    /// 1. If `model == nil` → `super.draw(rect)` and return.
    /// 2. Otherwise `CGContextClearRect(rect)`, build an `NSAttributedString`
    ///    from `model.text` with font / paragraph-style / foreground-color
    ///    attributes, then draw in THREE passes:
    ///    - pass 1: set shadow (`CGContextSetShadowWithColor` with
    ///      shadowOffset/shadowRadius/shadowColor), text mode `0` (fill), draw.
    ///    - pass 2: IF `borderWidth > 0` → text mode `1` (stroke),
    ///      `setLineWidth(borderWidth)`, `setLineJoin(.round)`,
    ///      `setLineCap(.round)`, `setStrokeColor(borderColor)`, draw.
    ///    - pass 3: text mode `0` (fill) again, draw the fill on top.
    /// The binary's `0x4014000000000000` (= 5.0) literal is the
    /// `drawWithRect:options:attributes:` options bitmask
    /// (`usesLineFragmentOrigin | usesFontLeading`).
    override public func draw(_ rect: CGRect) {
        guard let model else {
            super.draw(rect)
            return
        }

        guard let context = currentCGContext else {
            super.draw(rect)
            return
        }

        // Clear the rect before drawing the outlined text.
        context.clear(rect)

        // Build the attributed string from the model (font / paragraph / fill).
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: model.font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: model.textColor,
        ]
        let attributedString = NSAttributedString(string: model.text, attributes: attributes)

        // `drawWithRect:options:attributes:` options bitmask = 5.0 in the binary.
        let drawOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

        // Pass 1 — shadow + fill.
        context.saveGState()
        let shadowOffset = CGSize(width: model.shadowOffset, height: model.shadowOffset)
        context.setShadow(
            offset: shadowOffset,
            blur: model.shadowRadius,
            color: model.shadowColor.cgColor
        )
        context.setTextDrawingMode(.fill)
        attributedString.draw(with: rect, options: drawOptions, context: nil)
        context.restoreGState()

        // Pass 2 — border/stroke (only when borderWidth > 0).
        if model.borderWidth > 0 {
            context.saveGState()
            context.setTextDrawingMode(.stroke)
            context.setLineWidth(model.borderWidth)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.setStrokeColor(model.borderColor.cgColor)
            // Stroke pass uses the border color as the foreground glyph color.
            let strokeAttributes: [NSAttributedString.Key: Any] = [
                .font: model.font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: model.borderColor,
            ]
            let strokeString = NSAttributedString(string: model.text, attributes: strokeAttributes)
            strokeString.draw(with: rect, options: drawOptions, context: nil)
            context.restoreGState()
        }

        // Pass 3 — fill on top.
        context.saveGState()
        context.setTextDrawingMode(.fill)
        attributedString.draw(with: rect, options: drawOptions, context: nil)
        context.restoreGState()
    }

    /// Current CoreGraphics context for the active draw pass, bridged per platform.
    private var currentCGContext: CGContext? {
        #if canImport(UIKit)
        return UIGraphicsGetCurrentContext()
        #else
        return NSGraphicsContext.current?.cgContext
        #endif
    }

    // MARK: Intrinsic Size

    /// RE: `CustomDrawingLabel_textSizeCalculation` @ 0x10149E30C — intrinsic size.
    ///
    /// Re-rooted on the model (the binary's UIView base owns no `text`/`font`):
    /// derives the size from `model.text` / `model.font` via the attributed
    /// string's `boundingRect`, rounding up to whole pixels.
    public func textSize(constrainedTo maxSize: CGSize) -> CGSize {
        guard let model, !model.text.isEmpty else { return .zero }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: model.font,
        ]
        let attributedString = NSAttributedString(string: model.text, attributes: attributes)
        let boundingRect = attributedString.boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(
            width: ceil(boundingRect.width),
            height: ceil(boundingRect.height)
        )
    }
}
