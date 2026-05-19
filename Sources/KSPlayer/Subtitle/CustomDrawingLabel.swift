//
//  CustomDrawingLabel.swift
//  KSPlayer
//
//  Forward addition (RE): UILabel subclass with text stroke/outline
//  effects for subtitle rendering. Supports configurable stroke width
//  and color via a model property.
//
//  Binary: _TtC8KSPlayer18CustomDrawingLabel (8 functions)
//  RE source: Forward v1.3.15
//

#if canImport(UIKit)
import UIKit

public class CustomDrawingLabel: UILabel {
    // MARK: - Model

    public struct Model {
        public var strokeWidth: CGFloat = 0
        public var strokeColor: UIColor = .black
        public init() {}
    }

    public var model: Model = Model() {
        didSet { setNeedsDisplay() }
    }

    // MARK: - Convenience Init (RE: CustomDrawingLabel_convenienceInit @ 0x10149d490)

    public convenience init() {
        self.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    // MARK: - Init (RE: CustomDrawingLabel_initWithFrame @ 0x10149d634)

    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    // RE: CustomDrawingLabel_initWithCoder @ 0x10149d880
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    // MARK: - Draw (RE: CustomDrawingLabel_drawRect @ 0x10149da28)

    override public func drawText(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            super.drawText(in: rect)
            return
        }

        let strokeWidth = model.strokeWidth
        guard strokeWidth > 0 else {
            super.drawText(in: rect)
            return
        }

        let scaledStroke = strokeWidth * UITraitCollection.current.displayScale
        context.setLineWidth(scaledStroke)
        context.setLineJoin(.round)
        context.setTextDrawingMode(.stroke)

        let strokeColor = model.strokeColor
        self.textColor = strokeColor
        super.drawText(in: rect)

        context.setTextDrawingMode(.fill)
        self.textColor = textColor
        super.drawText(in: rect)
    }

    // MARK: - Text Size (RE: CustomDrawingLabel_textSizeCalculation @ 0x10149e30c)

    public func textSize(constrainedTo maxSize: CGSize) -> CGSize {
        guard let text = self.text, !text.isEmpty else { return .zero }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font as Any
        ]
        let boundingRect = (text as NSString).boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return CGSize(
            width: ceil(boundingRect.width),
            height: ceil(boundingRect.height)
        )
    }
}
#endif
