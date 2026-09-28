//
//  dovi_rpu_shim.c
//  KSPlayer — DOVIRPUShim
//
//  C shim implementation bridging FFmpeg's private DV RPU parser APIs
//  into a safe interface for Swift.
//
//  RE: the binary's Phase-2 DV chain (decode loop @ 0x101a6ce44). NOTE: the
//  addresses below are CORRECTED — the prior TrackDecode.md anchors
//  (0x102402568 / 0x10150c0a4) were WRONG (font/glyph code); confirmed by the
//  1B.1 deterministic audit (unique-string anchor + static-archive fingerprint):
//    ff_dovi_rpu_parse(ctx, buf, outPos, 0)            @ 0x102a3b9ac
//    size = ff_dovi_get_metadata(ctx, &outPtr)         @ 0x102a3b744
//    serialized = convertAVDOVIToKSDOVIMetadata(outPtr) @ 0x101b31c6c  (KS serializer)
//    memmove(tempBuf, serialized, 0xBC0)               // 3008 bytes
//    memcpy(self+0x50, tempBuf, 0xBC0)
//  Steps 1 (parse) and 2 (get_metadata) are wrapped here; the serialize +
//  stage steps (convertAVDOVIToKSDOVIMetadata @ 0x101b31c6c) live on the
//  Swift side in the decode loop.
//
//  This shim re-declares the private function prototypes and lets the
//  linker resolve them against the statically linked Libavcodec/Libavutil.
//

#include "dovi_rpu_shim.h"
#include <stddef.h>

// ── Inline-size guards (deterministic, compile-time) ──
// The reconstructed Swift fields embed these types BY VALUE; their sizes MUST equal the
// binary's inline reservations (VideoToolboxDecode: doviData@+0x50 = 3008 B; doviContext@
// +0xc10 = 224 B, i.e. the span to the next field `frames`@+0xcf0). If a future FFmpegKit
// bump changes one of these imported layouts, a guard fires at build time, before any
// silent class-layout drift.
_Static_assert(sizeof(KSDOVIDMData) == 0x28, "KSDOVIDMData must be 0x28 B");
_Static_assert(_Alignof(KSDOVIDMData) == 4, "KSDOVIDMData must be 4-byte aligned");

_Static_assert(sizeof(KSDOVIReshapeData) == 0x3b0, "KSDOVIReshapeData must be 0x3b0 B");
_Static_assert(_Alignof(KSDOVIReshapeData) == 16, "KSDOVIReshapeData must be 16-byte aligned");
_Static_assert(offsetof(KSDOVIReshapeData, coeffs) == 0x000, "KSDOVIReshapeData.coeffs offset");
_Static_assert(offsetof(KSDOVIReshapeData, mmr) == 0x080, "KSDOVIReshapeData.mmr offset");
_Static_assert(offsetof(KSDOVIReshapeData, pivots) == 0x380, "KSDOVIReshapeData.pivots offset");
_Static_assert(offsetof(KSDOVIReshapeData, lo) == 0x39c, "KSDOVIReshapeData.lo offset");
_Static_assert(offsetof(KSDOVIReshapeData, hi) == 0x3a0, "KSDOVIReshapeData.hi offset");
_Static_assert(offsetof(KSDOVIReshapeData, min_order) == 0x3a4, "KSDOVIReshapeData.min_order offset");
_Static_assert(offsetof(KSDOVIReshapeData, max_order) == 0x3a5, "KSDOVIReshapeData.max_order offset");
_Static_assert(offsetof(KSDOVIReshapeData, num_pivots) == 0x3a6, "KSDOVIReshapeData.num_pivots offset");
_Static_assert(offsetof(KSDOVIReshapeData, has_poly) == 0x3a7, "KSDOVIReshapeData.has_poly offset");
_Static_assert(offsetof(KSDOVIReshapeData, has_mmr) == 0x3a8, "KSDOVIReshapeData.has_mmr offset");
_Static_assert(offsetof(KSDOVIReshapeData, mmr_single) == 0x3a9, "KSDOVIReshapeData.mmr_single offset");

_Static_assert(sizeof(KSDOVIMetadata) == 0xbc0, "KSDOVIMetadata must be 0xbc0 B (binary inline)");
_Static_assert(_Alignof(KSDOVIMetadata) == 16, "KSDOVIMetadata must be 16-byte aligned");
_Static_assert(offsetof(KSDOVIMetadata, disable_residual_flag) == 0x00, "KSDOVIMetadata.disable_residual_flag offset");
_Static_assert(offsetof(KSDOVIMetadata, nonlinear) == 0x10, "KSDOVIMetadata.nonlinear offset");
_Static_assert(offsetof(KSDOVIMetadata, linear) == 0x40, "KSDOVIMetadata.linear offset");
_Static_assert(offsetof(KSDOVIMetadata, nonlinear_offset) == 0x70, "KSDOVIMetadata.nonlinear_offset offset");
_Static_assert(offsetof(KSDOVIMetadata, minLuminance) == 0x80, "KSDOVIMetadata.minLuminance offset");
_Static_assert(offsetof(KSDOVIMetadata, maxLuminance) == 0x84, "KSDOVIMetadata.maxLuminance offset");
_Static_assert(offsetof(KSDOVIMetadata, dm) == 0x88, "KSDOVIMetadata.dm offset");
_Static_assert(offsetof(KSDOVIMetadata, comp) == 0xb0, "KSDOVIMetadata.comp offset");
_Static_assert(sizeof(DOVIContext) == 224,     "DOVIContext must be 224 B (binary inline 0xE0; dovi_rpu.h sizeof)");

// ── Private FFmpeg API declarations ──
// Defined in libavcodec/dovi_rpu.h (not shipped in FFmpegKit public headers); the symbols
// exist in the Libavcodec static archive (nm: T). Forward calls them directly from Swift:
//   ff_dovi_rpu_parse    @ 0x102a3b9ac (8632 B)  ← VideoToolboxDecode.decodeFrame 0x101a6d0b8
//   ff_dovi_get_metadata @ 0x102a3b744 (452 B)   ← VideoToolboxDecode.decodeFrame 0x101a6d0f4
//   ff_dovi_ctx_unref    @ 0x102a3b4e0 (236 B)   ← VideoToolboxDecode shutdown     0x101a6ece4
// (sizes equal the FFmpegKit archive's dovi_rpu.o / dovi_rpudec.o bodies, ffmpeg_lib_index by_sym).
// No ks_dovi_* wrapper exists in Forward, so none is defined here.
extern void ff_dovi_ctx_unref(DOVIContext *ctx);
extern int ff_dovi_rpu_parse(DOVIContext *ctx, const uint8_t *rpu, size_t rpu_size, int err_recognition);
extern int ff_dovi_get_metadata(DOVIContext *ctx, AVDOVIMetadata **out_metadata);
