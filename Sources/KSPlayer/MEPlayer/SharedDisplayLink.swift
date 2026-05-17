//
//  SharedDisplayLink.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 SharedDisplayLinkDriver — singleton display link
//  that multiple consumers subscribe to, avoiding duplicate CADisplayLink instances.
//

import Foundation
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

/// Shared display link driver allowing multiple render targets to synchronize
/// to a single CADisplayLink without creating redundant timers.
public final class SharedDisplayLink: NSObject {
    public static let shared = SharedDisplayLink()

    public struct Subscription {
        let id: UUID
    }

    private var displayLink: CADisplayLink?
    private var subscribers = [(id: UUID, callback: () -> Void)]()
    private let lock = NSLock()
    private var preferredFPS: Float = 60

    private override init() {
        super.init()
    }

    /// Subscribe to display link callbacks. Returns a subscription token for unsubscribing.
    public func subscribe(_ callback: @escaping () -> Void) -> Subscription {
        lock.lock()
        defer { lock.unlock() }
        let sub = Subscription(id: UUID())
        subscribers.append((id: sub.id, callback: callback))
        if displayLink == nil {
            startDisplayLink()
        }
        return sub
    }

    /// Remove a subscription. Display link stops when no subscribers remain.
    public func unsubscribe(_ subscription: Subscription) {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeAll { $0.id == subscription.id }
        if subscribers.isEmpty {
            stopDisplayLink()
        }
    }

    /// Update preferred frame rate (max subscriber FPS wins)
    public func updatePreferredFPS(_ fps: Float) {
        lock.lock()
        defer { lock.unlock() }
        preferredFPS = max(preferredFPS, fps)
        #if canImport(UIKit)
        if #available(iOS 15.0, tvOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: fps,
                maximum: 2 * fps,
                __preferred: fps
            )
        } else {
            displayLink?.preferredFramesPerSecond = Int(fps)
        }
        #endif
    }

    /// Current timestamp from the display link
    public var timestamp: CFTimeInterval {
        displayLink?.timestamp ?? CACurrentMediaTime()
    }

    /// Duration of a single frame at current refresh rate
    public var frameDuration: CFTimeInterval {
        displayLink?.duration ?? (1.0 / 60.0)
    }

    @objc private func tick() {
        lock.lock()
        let callbacks = subscribers.map(\.callback)
        lock.unlock()
        for cb in callbacks {
            cb()
        }
    }

    private func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        preferredFPS = 60
    }
}
