//
//  NALUnitParser.swift
//  KSPlayer
//
//  L7 lane 18: no declarations. Forward has no file of this name; the NAL parser it stubbed
//  (0x101a0c470 Annex-B / 0x101a0ce98 length-prefixed, with 0x101a0bfdc / 0x101a0c0b0 / 0x101a0d2f8)
//  lives in Forward's AVFoundationExtension.swift as PacketNalData members, and the hand-made
//  NALEntry is replaced by PacketNalData.NALUnit (same 24-byte layout: type @+0, start @+8, count @+0x10).
//  The file stays as a comment-only stub because the lane tooling cannot delete files.
//
