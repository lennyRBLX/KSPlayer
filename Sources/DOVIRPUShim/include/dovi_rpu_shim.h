//
//  dovi_rpu_shim.h
//  KSPlayer — DOVIRPUShim
//
//  C shim exposing ff_dovi_rpu_parse and related private FFmpeg APIs.
//  The binary (v1.3.17) calls these directly because it statically links
//  FFmpeg. FFmpegKit ships prebuilt xcframeworks with these symbols linked
//  in but not exposed through public headers. This shim re-declares the
//  function prototypes so the linker resolves them at build time.
//
//  RE references (Forward 1.3.17, image base 0x100000000). Addresses CORRECTED
//  per the 1B.1 deterministic audit (unique-string anchor + static-archive
//  fingerprint) and the FFmpeg-symbol oracle; the prior TrackDecode.md anchors
//  (0x1024027d0 / 0x102402568 / 0x10150c0a4 / 0x10140608c) were WRONG — they
//  resolve to font/glyph/ORM code, not DV functions:
//    decode loop (rpu_parse → get_metadata → serialize chain) @ 0x101a6ce44
//    ff_dovi_rpu_parse      — definition @ 0x102a3b9ac.
//    ff_dovi_get_metadata   — definition @ 0x102a3b744. Realizes
//                             `int ff_dovi_get_metadata(DOVIContext*, AVDOVIMetadata**)`;
//                             allocates via av_dovi_metadata_alloc @ 0x10323b430.
//    convertAVDOVIToKSDOVIMetadata — @ 0x101b31c6c (KS-side serializer that
//                             flattens the AVDOVIMetadata into the 3008-byte
//                             KSDOVIMetadata GPU buffer). Caller responsibility,
//                             not part of this shim.
//

#ifndef DOVI_RPU_SHIM_H
#define DOVI_RPU_SHIM_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <simd/simd.h>

// DOVIContext: FFmpeg's private DV parser context (real def: libavcodec/dovi_rpu.h).
// The binary embeds it BY VALUE inline — 224 B at VideoToolboxDecode's +0xc10
// (frames@+0xcf0 − doviContext@+0xc10 = 0xe0 = 224). sizeof(DOVIContext) == 224 in this
// FFmpeg 8.1.1 build, confirmed three ways: (1) the binary inline span; (2) the real
// dovi_rpu.h via a self-contained sizeof compile (vdr[DOVI_MAX_DM_ID+1] = 16 ptrs = 128 B
// dominates → 224); (3) the _Static_assert in dovi_rpu_shim.c. Held OPAQUE (real fields
// private) — we mirror only the SIZE so the Swift field is a faithful 224 B inline value;
// the extern ff_dovi_*(DOVIContext*) calls stay ABI-compatible (same size).
typedef struct DOVIContext { uint8_t _opaque[224]; } DOVIContext;

// KSDOVIMetadata: the KS-side flattened DV-metadata GPU buffer the serializer
// convertAVDOVIToKSDOVIMetadata (@0x101b31c6c) produces. The imported C layout is
// embedded inline by Swift and retains the nested metadata fields used by the renderer.
typedef struct KSDOVIDMData {
    float min_pq;
    float max_pq;
    float avg_pq;
    float target_max_pq;
    float slope;
    float offset;
    float power;
    float chroma_weight;
    float saturation_gain;
    float ms_weight;
} KSDOVIDMData;

typedef struct KSDOVIReshapeData {
    simd_float4 coeffs[8];
    simd_float4 mmr[8 * 6];
    float pivots[7];
    float lo;
    float hi;
    uint8_t min_order;
    uint8_t max_order;
    uint8_t num_pivots;
    bool has_poly;
    bool has_mmr;
    bool mmr_single;
} KSDOVIReshapeData;

typedef struct KSDOVIMetadata {
    uint8_t disable_residual_flag;
    simd_float3x3 nonlinear;
    simd_float3x3 linear;
    simd_float3 nonlinear_offset;
    float minLuminance;
    float maxLuminance;
    KSDOVIDMData dm;
    KSDOVIReshapeData comp[3];
} KSDOVIMetadata;

// AVDOVIMetadata from libavutil/dovi_meta.h (public).
// Try framework-style include first, fall back to bare header.
#if __has_include(<Libavutil/dovi_meta.h>)
#include <Libavutil/dovi_meta.h>
#elif __has_include(<libavutil/dovi_meta.h>)
#include <libavutil/dovi_meta.h>
#else
#include <dovi_meta.h>
#endif

// ── Raw private FFmpeg DV RPU APIs (Swift-callable) ──
// The 1.3.17 binary calls these DIRECTLY on the inline DOVIContext (NOT the ks_dovi_* heap
// wrappers): VTBox.decodeFrame @0x101a6ce44 does
//   ff_dovi_rpu_parse(&doviContext, rpu, sz, 0) -> ff_dovi_get_metadata(&doviContext, &out)
// and the shutdown DV-tail does ff_dovi_ctx_unref(&doviContext). Declared here (not just in the
// .c) so the Swift decode loop can invoke them with `&doviContext` (inout -> the exclusive
// begin/endAccess). Linker resolves them from the static Libavcodec (nm: T). Sigs: libavcodec/dovi_rpu.h.
int ff_dovi_rpu_parse(DOVIContext *ctx, const uint8_t *rpu, size_t rpu_size, int err_recognition);
int ff_dovi_get_metadata(DOVIContext *ctx, AVDOVIMetadata **out_metadata);
void ff_dovi_ctx_unref(DOVIContext *ctx);

// The former ks_dovi_* heap wrappers (ctx_alloc/free/flush, rpu_parse, get_metadata,
// metadata_free) were removed: Forward has no such functions — every ff_dovi_* call site
// (0x101a6ce44 parse/get_metadata, 0x101a6ec80 ctx_unref) calls FFmpeg directly on the inline
// DOVIContext, and ff_dovi_ctx_flush (their flush target) is not even linked into Forward.

#endif /* DOVI_RPU_SHIM_H */
