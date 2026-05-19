//
//  PaddedLabel.swift
//  KSPlayer
//
//  Forward addition (RE): UILabel subclass that adds configurable
//  padding insets around the text content area, with optional
//  text stroke/outline rendering.
//
//  Binary: _TtC8KSPlayer11PaddedLabel (1 function)
//  RE source: Forward v1.3.15
//

#if canImport(UIKit)
import UIKit

public class PaddedLabel: UILabel {
    public var padding = UIEdgeInsets.zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    // RE: PaddedLabel_drawTextInRect_impl @ 0x1013e66f0
    override public func drawText(in rect: CGRect) {
        let insetRect = CGRect(
            x: rect.origin.x + padding.left,
            y: rect.origin.y + padding.top,
            width: rect.width - padding.left - padding.right,
            height: rect.height - padding.top - padding.bottom
        )

        guard let context = UIGraphicsGetCurrentContext() else {
            super.drawText(in: insetRect)
            return
        }

        let strokeWidth = Self.strokeWidth
        if strokeWidth > 0 {
            let scaledStroke = strokeWidth * UITraitCollection.current.displayScale
            context.setLineWidth(scaledStroke)
            context.setLineJoin(.round)
            context.setTextDrawingMode(.stroke)

            let savedColor = textColor
            textColor = Self.strokeColor
            super.drawText(in: insetRect)

            context.setTextDrawingMode(.fill)
            textColor = savedColor
            super.drawText(in: insetRect)
        } else {
            super.drawText(in: insetRect)
        }
    }

    override public var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + padding.left + padding.right,
            height: size.height + padding.top + padding.bottom
        )
    }

    // RE: Global stroke config (from binary globals)
    @MainActor static var strokeWidth: CGFloat = 0
    @MainActor static var strokeColor: UIColor = .black
}
#endif
