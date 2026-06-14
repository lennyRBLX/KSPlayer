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
import UIKit

@MainActor
final class MotionSensor {
    static let shared = MotionSensor()
    private let manager = CMMotionManager()
    private let worldToInertialReferenceFrame = simd_float4x4(euler: -90, y: 0, z: 90)
    private var deviceToDisplay = simd_float4x4.identity
    private let defaultRadiansY: Float
    /// RE: 0x10146c9c0 (MotionSensor.updateOrientation, 1.3.15)
    /// Binary values: 0x43340000=180deg(case2), 0xc2b40000=-90deg(case3=landscapeLeft), 0x42b40000=+90deg(case4=landscapeRight).
    private var orientation = UIInterfaceOrientation.unknown {
        didSet {
            if oldValue != orientation {
                switch orientation {
                case .portraitUpsideDown:
                    deviceToDisplay = simd_float4x4(euler: 0, y: 0, z: 180)
                case .landscapeLeft:
                    deviceToDisplay = simd_float4x4(euler: 0, y: 0, z: -90)
                case .landscapeRight:
                    deviceToDisplay = simd_float4x4(euler: 0, y: 0, z: 90)
                default:
                    deviceToDisplay = simd_float4x4.identity
                }
            }
        }
    }

    /// RE: 0x10146ca60 (MotionSensor.init, 1.3.15)
    /// Binary: landscapeRight(case4)=+pi/2 (0x3fc90fda), landscapeLeft(case3)=-pi/2 (0xbfc90fda).
    private init() {
        switch KSOptions.windowScene?.interfaceOrientation {
        case .landscapeRight:
            defaultRadiansY = .pi / 2
        case .landscapeLeft:
            defaultRadiansY = -.pi / 2
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

    /// RE: 0x10146cb94 (MotionSensor device-motion matrix builder, 1.3.15)
    /// Transform chain: rollY(defaultRadiansY) . deviceToDisplay . (deviceRotationMatrix . worldToInertialReferenceFrame)
    /// Binary instruction trace confirms NO transpose on the device rotation matrix.
    /// FUN_101472174 builds a Y-axis rotation (matches init(rotationY:) column layout).
    func matrix() -> simd_float4x4? {
        if var matrix = manager.deviceMotion.flatMap(simd_float4x4.init(motion:)) {
            matrix *= worldToInertialReferenceFrame
            orientation = KSOptions.windowScene?.interfaceOrientation ?? .portrait
            matrix = deviceToDisplay * matrix
            matrix = matrix.rotateY(radians: defaultRadiansY)
            return matrix
        }
        return nil
    }
}

public extension simd_float4x4 {
    /// RE: 0x10146cb94 (CMDeviceMotion narrowing step inside MotionSensor matrix builder, 1.3.15)
    /// Binary: [deviceMotion attitude] -> [attitude rotationMatrix] -> fcvt-narrowed to floats.
    init(motion: CMDeviceMotion) {
        self.init(rotation: motion.attitude.rotationMatrix)
    }

    /// RE: 0x10146cc5c (float packing with bottom-right -1.0 inside FUN_10146cb94, 1.3.15)
    /// Binary: CMRotationMatrix 9 doubles fcvtn-narrowed to floats, packed into simd_float4x4
    /// with fmov v2.4S,#0xbf800000 (-1.0) at bottom-right of row 2.
    init(rotation: CMRotationMatrix) {
        self.init(SIMD4<Float>(Float(rotation.m11), Float(rotation.m12), Float(rotation.m13), 0.0),
                  SIMD4<Float>(Float(rotation.m21), Float(rotation.m22), Float(rotation.m23), 0.0),
                  SIMD4<Float>(Float(rotation.m31), Float(rotation.m32), Float(rotation.m33), -1),
                  SIMD4<Float>(0, 0, 0, 1))
    }
}
#endif
