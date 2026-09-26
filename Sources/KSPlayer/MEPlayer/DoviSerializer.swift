//
//  DoviSerializer.swift
//  KSPlayer
//
//  P3a Phase B prereq — the KS-side DV-metadata serializer (stub; body → DV-render).
//

import DOVIRPUShim
import Libavutil

/// Flattens the FFmpeg-decoded `AVDOVIMetadata` into the 3008-byte `KSDOVIMetadata` GPU buffer.
///
/// Binary: `FUN_101b31c6c` (455 instr, sret return, free/global function — decompile-confirmed;
/// shared by 3 decode callers). The float-flattening body (mapping / color / DM-spline blocks →
/// the 3008-byte float layout) is DEFERRED → DV-render, where the `KSDOVIMetadata` field-layout is
/// reconstructed. This stub returns a zeroed buffer (matching the binary's leading
/// `bzero(out, 0xBC0)`) so the decode-loop callers build and are body-auditable.
func convertAVDOVIToKSDOVIMetadata(_ metadata: UnsafePointer<AVDOVIMetadata>) -> KSDOVIMetadata {
    let header = av_dovi_get_header(metadata)!.pointee
    let mapping = av_dovi_get_mapping(metadata)!
    let color = av_dovi_get_color(metadata)!

    func yccMatrixValue(_ index: Int) -> AVRational {
        withUnsafePointer(to: &color.pointee.ycc_to_rgb_matrix) { pointer in
            pointer.withMemoryRebound(to: AVRational.self, capacity: 9) { values in
                values[index]
            }
        }
    }

    func yccOffsetValue(_ index: Int) -> AVRational {
        withUnsafePointer(to: &color.pointee.ycc_to_rgb_offset) { pointer in
            pointer.withMemoryRebound(to: AVRational.self, capacity: 3) { values in
                values[index]
            }
        }
    }

    func rgbMatrixValue(_ index: Int) -> AVRational {
        withUnsafePointer(to: &color.pointee.rgb_to_lms_matrix) { pointer in
            pointer.withMemoryRebound(to: AVRational.self, capacity: 9) { values in
                values[index]
            }
        }
    }

    var result = KSDOVIMetadata()
    let pivotScale = Float(1) / Float((1 << Int(header.bl_bit_depth)) - 1)
    let coefficientScale = Float(1) / Float(1 << Int(header.coef_log2_denom))

    withUnsafeMutableBytes(of: &result) { output in
        output.storeBytes(of: header.disable_residual_flag, toByteOffset: 0x000, as: UInt8.self)

        for column in 0..<3 {
            for row in 0..<3 {
                let ycc = yccMatrixValue(row * 3 + column)
                let yccValue = Float(Double(ycc.num) / Double(ycc.den))
                output.storeBytes(
                    of: yccValue,
                    toByteOffset: 0x010 + column * 0x10 + row * 4,
                    as: Float.self
                )

                let rgb = rgbMatrixValue(row * 3 + column)
                let rgbValue = Float(Double(rgb.num) / Double(rgb.den))
                output.storeBytes(
                    of: rgbValue,
                    toByteOffset: 0x040 + column * 0x10 + row * 4,
                    as: Float.self
                )
            }
        }

        for row in 0..<3 {
            let offset = yccOffsetValue(row)
            let value = -Float(Double(offset.num) / Double(offset.den))
            output.storeBytes(of: value, toByteOffset: 0x070 + row * 4, as: Float.self)
        }

        output.storeBytes(of: Float(color.pointee.source_min_pq), toByteOffset: 0x080, as: Float.self)
        output.storeBytes(of: Float(color.pointee.source_max_pq), toByteOffset: 0x084, as: Float.self)

        if let level1 = av_dovi_find_level(metadata, 1) {
            let level3 = av_dovi_find_level(metadata, 3)
            let level8 = av_dovi_find_level(metadata, 8)
            let level2 = av_dovi_find_level(metadata, 2)
            var minPQ = Int(level1.pointee.l1.min_pq)
            var maxPQ = Int(level1.pointee.l1.max_pq)
            var avgPQ = Int(level1.pointee.l1.avg_pq)

            if let level3 = level3 {
                minPQ += Int(level3.pointee.l3.min_pq_offset) - 2048
                maxPQ += Int(level3.pointee.l3.max_pq_offset) - 2048
                avgPQ += Int(level3.pointee.l3.avg_pq_offset) - 2048
            }

            output.storeBytes(of: Float(minPQ) / Float(4095), toByteOffset: 0x088, as: Float.self)
            output.storeBytes(of: Float(maxPQ) / Float(4095), toByteOffset: 0x08c, as: Float.self)
            let average = Float(max(Double(Float(avgPQ) / Float(4095)), 0.0001))
            output.storeBytes(of: average, toByteOffset: 0x090, as: Float.self)

            if let level2 = level2 {
                let targetMaxPQ = Float(Double(level2.pointee.l2.target_max_pq) / 4095.0)
                output.storeBytes(of: targetMaxPQ, toByteOffset: 0x094, as: Float.self)
            }

            if let level8 = level8 {
                let trim = level8.pointee.l8
                output.storeBytes(of: Float(trim.trim_slope) / Float(2048), toByteOffset: 0x098, as: Float.self)
                output.storeBytes(of: Float(trim.trim_offset) / Float(2048) - Float(1), toByteOffset: 0x09c, as: Float.self)
                output.storeBytes(of: Float(trim.trim_power) / Float(2048), toByteOffset: 0x0a0, as: Float.self)
                output.storeBytes(of: Float(trim.trim_chroma_weight) / Float(2048), toByteOffset: 0x0a4, as: Float.self)
                output.storeBytes(of: Float(trim.trim_saturation_gain) / Float(2048), toByteOffset: 0x0a8, as: Float.self)
                output.storeBytes(of: Float(trim.ms_weight) / Float(2048) - Float(1), toByteOffset: 0x0ac, as: Float.self)
            } else if let level2 = level2 {
                let trim = level2.pointee.l2
                output.storeBytes(of: Float(trim.trim_slope) / Float(2048), toByteOffset: 0x098, as: Float.self)
                output.storeBytes(of: Float(trim.trim_offset) / Float(2048) - Float(1), toByteOffset: 0x09c, as: Float.self)
                output.storeBytes(of: Float(trim.trim_power) / Float(2048), toByteOffset: 0x0a0, as: Float.self)
                output.storeBytes(of: Float(trim.trim_chroma_weight) / Float(2048), toByteOffset: 0x0a4, as: Float.self)
                output.storeBytes(of: Float(trim.trim_saturation_gain) / Float(2048), toByteOffset: 0x0a8, as: Float.self)
                let msWeight = trim.ms_weight == -1
                    ? Float(0)
                    : Float(trim.ms_weight) / Float(2048) - Float(1)
                output.storeBytes(of: msWeight, toByteOffset: 0x0ac, as: Float.self)
            }
        }

        withUnsafeMutablePointer(to: &mapping.pointee.curves) { curveTuple in
            curveTuple.withMemoryRebound(to: AVDOVIReshapingCurve.self, capacity: 3) { curves in
                for component in 0..<3 {
                    let curve = curves.advanced(by: component)
                    let curveRaw = UnsafeRawPointer(curve)
                    let numPivotsByte = curve.pointee.num_pivots
                    let numPivots = Int(numPivotsByte)
                    let componentOffset = 0x0b0 + component * 0x3b0

                    func readUInt8(at offset: Int) -> UInt8 {
                        curveRaw.advanced(by: offset).assumingMemoryBound(to: UInt8.self).pointee
                    }

                    func readUInt16(at offset: Int) -> UInt16 {
                        curveRaw.advanced(by: offset).assumingMemoryBound(to: UInt16.self).pointee
                    }

                    func readInt64(at offset: Int) -> Int64 {
                        curveRaw.advanced(by: offset).assumingMemoryBound(to: Int64.self).pointee
                    }

                    func scaledPivot(_ index: Int) -> Float {
                        let pivot = readUInt16(at: 2 + index * MemoryLayout<UInt16>.stride)
                        return Float(pivot) * pivotScale
                    }

                    if numPivots == 0 {
                        continue
                    }

                    let firstPivot = scaledPivot(0)
                    if numPivots == 1 {
                        output.storeBytes(of: firstPivot, toByteOffset: componentOffset + 0x39c, as: Float.self)
                        output.storeBytes(of: firstPivot, toByteOffset: componentOffset + 0x3a0, as: Float.self)
                        output.storeBytes(of: UInt8(3), toByteOffset: componentOffset + 0x3a4, as: UInt8.self)
                        output.storeBytes(of: UInt8(1), toByteOffset: componentOffset + 0x3a5, as: UInt8.self)
                        output.storeBytes(of: numPivotsByte, toByteOffset: componentOffset + 0x3a6, as: UInt8.self)
                        output.storeBytes(of: UInt8(0), toByteOffset: componentOffset + 0x3a7, as: UInt8.self)
                        output.storeBytes(of: UInt8(0), toByteOffset: componentOffset + 0x3a8, as: UInt8.self)
                        output.storeBytes(of: UInt8(1), toByteOffset: componentOffset + 0x3a9, as: UInt8.self)
                        continue
                    }

                    let lastPivot = scaledPivot(numPivots - 1)
                    output.storeBytes(of: firstPivot, toByteOffset: componentOffset + 0x39c, as: Float.self)
                    output.storeBytes(of: lastPivot, toByteOffset: componentOffset + 0x3a0, as: Float.self)

                    if numPivots > 2 {
                        for pivotIndex in 1..<(numPivots - 1) {
                            let pivot = scaledPivot(pivotIndex)
                            output.storeBytes(
                                of: pivot,
                                toByteOffset: componentOffset + 0x380 + (pivotIndex - 1) * MemoryLayout<Float>.stride,
                                as: Float.self
                            )
                        }

                        if numPivots < 9 {
                            for pivotIndex in (numPivots - 2)..<7 {
                                output.storeBytes(
                                    of: Float(1_000_000_000),
                                    toByteOffset: componentOffset + 0x380 + pivotIndex * MemoryLayout<Float>.stride,
                                    as: Float.self
                                )
                            }
                        }
                    }

                    var minOrder: UInt8 = 3
                    var maxOrder: UInt8 = 1
                    var hasPoly = false
                    var hasMMR = false
                    var mmrSingle = true
                    var mmrCoefficientIndex = 0

                    withUnsafeTemporaryAllocation(of: Float.self, capacity: 21) { mmrScratch in
                        for piece in 0..<(numPivots - 1) {
                            let method = curveRaw
                                .advanced(by: 0x14 + piece * MemoryLayout<AVDOVIMappingMethod>.stride)
                                .assumingMemoryBound(to: AVDOVIMappingMethod.self)
                                .pointee
                            let descriptorOffset = componentOffset + piece * 0x10

                            if method == AV_DOVI_MAPPING_POLYNOMIAL {
                                let polyOrder = Int(readUInt8(at: 0x34 + piece))
                                for coefficientIndex in 0..<3 where coefficientIndex <= polyOrder {
                                    let coefficient = readInt64(
                                        at: 0x40 + piece * 3 * MemoryLayout<Int64>.stride
                                            + coefficientIndex * MemoryLayout<Int64>.stride
                                    )
                                    let value = Float(coefficient) * coefficientScale
                                    output.storeBytes(
                                        of: value,
                                        toByteOffset: descriptorOffset + coefficientIndex * MemoryLayout<Float>.stride,
                                        as: Float.self
                                    )
                                }
                                hasPoly = true
                            } else if method == AV_DOVI_MAPPING_MMR {
                                let mmrOrder = readUInt8(at: 0x100 + piece)
                                let constant = readInt64(
                                    at: 0x108 + piece * MemoryLayout<Int64>.stride
                                )

                                for orderIndex in 0..<Int(mmrOrder) {
                                    for coefficientIndex in 0..<7 {
                                        let coefficient = readInt64(
                                            at: 0x148
                                                + piece * 3 * 7 * MemoryLayout<Int64>.stride
                                                + orderIndex * 7 * MemoryLayout<Int64>.stride
                                                + coefficientIndex * MemoryLayout<Int64>.stride
                                        )
                                        mmrScratch.baseAddress!
                                            .advanced(by: orderIndex * 7 + coefficientIndex)
                                            .pointee = Float(coefficient) * coefficientScale
                                    }
                                }

                                output.storeBytes(
                                    of: Float(constant) * coefficientScale,
                                    toByteOffset: descriptorOffset,
                                    as: Float.self
                                )
                                output.storeBytes(
                                    of: Float(mmrCoefficientIndex),
                                    toByteOffset: descriptorOffset + MemoryLayout<Float>.stride,
                                    as: Float.self
                                )
                                output.storeBytes(
                                    of: Float(mmrOrder),
                                    toByteOffset: descriptorOffset + 3 * MemoryLayout<Float>.stride,
                                    as: Float.self
                                )

                                if mmrOrder < minOrder {
                                    minOrder = mmrOrder
                                }
                                if mmrOrder > maxOrder {
                                    maxOrder = mmrOrder
                                }
                                if hasMMR {
                                    mmrSingle = false
                                }
                                hasMMR = true
                                if mmrOrder != 0 {
                                    mmrCoefficientIndex += Int(mmrOrder) * 2
                                }
                            }
                        }
                    }

                    output.storeBytes(of: minOrder, toByteOffset: componentOffset + 0x3a4, as: UInt8.self)
                    output.storeBytes(of: maxOrder, toByteOffset: componentOffset + 0x3a5, as: UInt8.self)
                    output.storeBytes(of: numPivotsByte, toByteOffset: componentOffset + 0x3a6, as: UInt8.self)
                    output.storeBytes(of: UInt8(hasPoly ? 1 : 0), toByteOffset: componentOffset + 0x3a7, as: UInt8.self)
                    output.storeBytes(of: UInt8(hasMMR ? 1 : 0), toByteOffset: componentOffset + 0x3a8, as: UInt8.self)
                    output.storeBytes(of: UInt8(mmrSingle ? 1 : 0), toByteOffset: componentOffset + 0x3a9, as: UInt8.self)
                }
            }
        }
    }

    return result
}
