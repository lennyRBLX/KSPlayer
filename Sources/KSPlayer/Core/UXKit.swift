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

@objc public enum ControlEvents: Int {
    case touchDown
    case touchUpInside
    case touchCancel
    case valueChanged
    case primaryActionTriggered
    case mouseEntered
    case mouseExited
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
