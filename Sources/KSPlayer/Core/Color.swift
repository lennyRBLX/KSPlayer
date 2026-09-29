//
//  Color.swift
//  KSPlayer
//
//  Split out of Utility.swift to match Forward 1.3.17: UIColor.data's `try!` reports
//  #fileID "KSPlayer/Color.swift" line 96 (0x60) — Forward 0x1019e86dc..0x1019e86f4.
//

import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Forward emission order (contiguous 0x1019e7f44..0x1019e87f4): init(rgb:alpha:) 0x1019e7f44,
// createImage(size:) 0x1019e7fa8, init?(assColor:) 0x1019e805c, init(abgr:) 0x1019e82dc,
// init(bgr:alpha:) 0x1019e8358, abgr 0x1019e83bc, assColor 0x1019e85a4, data 0x1019e861c,
// init?(data:) 0x1019e86fc. Declarations follow that order. Access is unchanged from the
// Utility.swift original (all members public).
public extension UIColor {
    convenience init(rgb hex: Int, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF)
        let green = CGFloat((hex >> 8) & 0xFF)
        let blue = CGFloat(hex & 0xFF)
        self.init(red: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
    }

    func createImage(size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        #if canImport(UIKit)
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(cgColor)
        context?.fill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!
        #else
        let image = NSImage(size: size)
        image.lockFocus()
        drawSwatch(in: CGRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
        #endif
    }

    convenience init?(assColor: String) {
        var colorString = assColor
        // 移除颜色字符串中的前缀 &H 和后缀 &
        if colorString.hasPrefix("&H") {
            colorString = String(colorString.dropFirst(2))
        }
        if colorString.hasSuffix("&") {
            colorString = String(colorString.dropLast())
        }
        if let hex = Scanner(string: colorString).scanInt(representation: .hexadecimal) {
            self.init(abgr: hex)
        } else {
            return nil
        }
    }

    convenience init(abgr hex: Int) {
        let alpha = 1 - (CGFloat(hex >> 24 & 0xFF) / 255)
        let blue = CGFloat((hex >> 16) & 0xFF)
        let green = CGFloat((hex >> 8) & 0xFF)
        let red = CGFloat(hex & 0xFF)
        self.init(red: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
    }

    convenience public init(bgr: Int, alpha: CGFloat) {
        let blue = CGFloat((bgr >> 16) & 0xFF)
        let green = CGFloat((bgr >> 8) & 0xFF)
        let red = CGFloat(bgr & 0xFF)
        self.init(red: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
    }

    public var abgr: Int {
        var red = CGFloat(0)
        var green = CGFloat(0)
        var blue = CGFloat(0)
        var alpha = CGFloat(0)
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        let a = 0xFF - Int(alpha * 255)
        return r | g << 8 | b << 16 | a << 24
    }

    public var assColor: String { String(format: "&H%08X", abgr) }

    // Forward 0x1019e861c: swift_unexpectedError("KSPlayer/Color.swift", 0x14, 1, line 0x60 = 96).
    public var data: Data {
        try! NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)
    }

    convenience public init?(data: Data) {
        guard let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) else {
            return nil
        }
        self.init(cgColor: color.cgColor)
    }
}
