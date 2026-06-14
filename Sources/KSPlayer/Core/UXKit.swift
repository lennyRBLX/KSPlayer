//
//  File.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension UIView {
    var backingLayer: CALayer? {
        #if !canImport(UIKit)
        wantsLayer = true
        #endif
        return layer
    }

    var cornerRadius: CGFloat {
        get {
            backingLayer?.cornerRadius ?? 0
        }
        set {
            backingLayer?.cornerRadius = newValue
        }
    }
}

/// KSPlayer's UIControl-event set, modeled as an `OptionSet` over raw `UInt`.
///
/// RE: §18.6 / §3322 (1.3.15) — recovered as an `OptionSet` struct, NOT a
/// sequential-`Int` `@objc` enum. Its members appear only as raw `UInt`
/// literals at use sites (e.g. `controlEvents = 0x40` = `.touchUpInside` in
/// `buildFullScreenLayout`, §1.4) — by design there are no `__swift5_fieldmd`
/// case records, which is why reflection reports "no cases."
///
/// Raw values mirror UIKit's `UIControl.Event` bit layout so the same literals
/// the binary registers (`0x40`, etc.) map onto named members. `.mouseEntered`
/// / `.mouseExited` are KSPlayer-custom (used by the AppKit `KSButton` shim);
/// they occupy the application-reserved high-bit range to avoid colliding with
/// real `UIControl.Event` bits.
///
/// Conforms to `Hashable` because the AppKit `KSButton` target/action table
/// (`AppKitExtend.swift`) keys its dictionary by `ControlEvents`.
public struct ControlEvents: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let touchDown = ControlEvents(rawValue: 1 << 0) // 0x1
    public static let touchUpInside = ControlEvents(rawValue: 1 << 6) // 0x40
    public static let touchCancel = ControlEvents(rawValue: 1 << 8) // 0x100
    public static let valueChanged = ControlEvents(rawValue: 1 << 12) // 0x1000
    public static let primaryActionTriggered = ControlEvents(rawValue: 1 << 13) // 0x2000
    public static let mouseEntered = ControlEvents(rawValue: 1 << 24) // app-reserved range
    public static let mouseExited = ControlEvents(rawValue: 1 << 25) // app-reserved range
}

protocol KSSliderDelegate: AnyObject {
    /**
     call when slider action trigged
     - parameter value:      progress
     - parameter event:       action
     */
    func slider(value: Double, event: ControlEvents)

    // MARK: - Pan-gesture surface
    //
    // Binary reference: these three methods are observed in the symbol table
    // via Swift mangled names referencing the `KSPanDirection` enum token
    // (`KSPanDirectionO`). They are the dispatch surface used by
    // `Components.VerticalPanGestureView` and the seek-bar pan path to deliver
    // axis-discriminated pan deltas back to the consumer.
    //
    // Default implementations are no-ops so existing conformers (PlayerView)
    // are not broken by adding the requirements.

    /// Pan gesture began. Mangled: `panGestureBegan(location:direction:)` —
    /// observed at string address `0x10473ed99`.
    func panGestureBegan(location: CGPoint, direction: KSPanDirection)

    /// Pan gesture changed. Mangled: `panGestureChanged(velocity:direction:)` —
    /// observed at string address `0x10473f817`.
    func panGestureChanged(velocity: CGPoint, direction: KSPanDirection)

    /// Translate a pan velocity into a seek-bar target value. Mangled:
    /// `panValue(velocity:direction:currentTime:totalTime:) -> Float` —
    /// observed at string address `0x1047385af`.
    func panValue(velocity: CGPoint,
                  direction: KSPanDirection,
                  currentTime: Float,
                  totalTime: Float) -> Float
}

extension KSSliderDelegate {
    func panGestureBegan(location _: CGPoint, direction _: KSPanDirection) {}
    func panGestureChanged(velocity _: CGPoint, direction _: KSPanDirection) {}
    func panValue(velocity: CGPoint,
                  direction _: KSPanDirection,
                  currentTime: Float,
                  totalTime: Float) -> Float {
        // Default: linear horizontal-axis mapping clamped to [0, totalTime].
        let delta = Float(velocity.x) * 0.5
        return max(0, min(totalTime, currentTime + delta))
    }
}
