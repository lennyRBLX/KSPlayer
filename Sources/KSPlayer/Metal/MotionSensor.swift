//
//  MotionSensor.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/13.
//

#if canImport(UIKit) && canImport(CoreMotion)
import CoreMotion
import Foundation
import simd
@preconcurrency import UIKit

// L7 lane 15: not @MainActor. SphereDisplayModel.set (nonisolated DisplayEnum witness, Forward 0x101a8c200) calls
// `shared` (swift_once 0x1044ed378 → 0x101a87ef0, no hop) and matrix() 0x101a880e4 directly; matrix() and init
// 0x101a87fc8 read UIApplication.shared.activeWindowScene (0x101a02f64) → interfaceOrientation with no executor
// check. `@preconcurrency import UIKit` is what lets that UIKit read typecheck here; `nonisolated(unsafe)` on
// `shared` is the Swift 6 spelling of Forward's unguarded once-global (no Sendable conformance is recorded).
final class MotionSensor {
    nonisolated(unsafe) static let shared = MotionSensor()
    private let manager = CMMotionManager()
    private let worldToInertialReferenceFrame = simd_float4x4(euler: -90, y: 0, z: 90)
    private var deviceToDisplay = simd_float4x4.identity
    private let defaultRadiansY: Float
    private var orientation = UIInterfaceOrientation.unknown {
        didSet {
            if oldValue != orientation {
                switch orientation {
                case .portraitUpsideDown:
                    deviceToDisplay = simd_float4x4(euler: 0, y: 0, z: 180)
                case .landscapeRight:
                    deviceToDisplay = simd_float4x4(euler: 0, y: 0, z: -90)
                case .landscapeLeft:
                    deviceToDisplay = simd_float4x4(euler: 0, y: 0, z: 90)
                default:
                    deviceToDisplay = simd_float4x4.identity
                }
            }
        }
    }

    private init() {
        switch UIApplication.shared.activeWindowScene?.interfaceOrientation {
        case .landscapeRight:
            defaultRadiansY = -.pi / 2
        case .landscapeLeft:
            defaultRadiansY = .pi / 2
        default:
            defaultRadiansY = 0
        }
    }

    func ready() -> Bool {
        manager.isDeviceMotionAvailable ? manager.isDeviceMotionActive : false
    }

    func start() {
        if manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive {
            manager.deviceMotionUpdateInterval = 1 / 60
            manager.startDeviceMotionUpdates()
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func matrix() -> simd_float4x4? {
        if var matrix = manager.deviceMotion.flatMap(simd_float4x4.init(motion:)) {
            matrix = matrix.transpose
            matrix *= worldToInertialReferenceFrame
            orientation = UIApplication.shared.activeWindowScene?.interfaceOrientation ?? .portrait
            matrix = deviceToDisplay * matrix
            matrix = matrix.rotateY(radians: defaultRadiansY)
            return matrix
        }
        return nil
    }
}

public extension simd_float4x4 {
    init(motion: CMDeviceMotion) {
        self.init(rotation: motion.attitude.rotationMatrix)
    }

    init(rotation: CMRotationMatrix) {
        self.init(SIMD4<Float>(Float(rotation.m11), Float(rotation.m12), Float(rotation.m13), 0.0),
                  SIMD4<Float>(Float(rotation.m21), Float(rotation.m22), Float(rotation.m23), 0.0),
                  SIMD4<Float>(Float(rotation.m31), Float(rotation.m32), Float(rotation.m33), -1),
                  SIMD4<Float>(0, 0, 0, 1))
    }
}
#endif
