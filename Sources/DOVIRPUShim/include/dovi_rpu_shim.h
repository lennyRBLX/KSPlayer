//
//  dovi_rpu_shim.h
//  KSPlayer — DOVIRPUShim
//
//  C shim exposing ff_dovi_rpu_parse and related private FFmpeg APIs.
//  The binary (v1.3.15) calls these directly because it statically links
//  FFmpeg. FFmpegKit ships prebuilt xcframeworks with these symbols linked
//  in but not exposed through public headers. This shim re-declares the
//  function prototypes so the linker resolves them at build time.
//
//  RE references:
//    TrackDecode.md L704-714 (Phase 2 DV RPU parsing chain)
//    Binary: ff_dovi_rpu_parse @ 0x10140608c callee
//    Binary: FUN_102402568 (dovi_rpu_get_header)
//    Binary: FUN_10150c0a4 (dovi_metadata_serialize)
//

#ifndef DOVI_RPU_SHIM_H
#define DOVI_RPU_SHIM_H

#include <stdint.h>
#include <stddef.h>

// Forward-declare the opaque DOVIContext used by FFmpeg's private DV parser.
// The actual struct definition is in libavcodec/dovi_rpu.h (not public).
typedef struct DOVIContext DOVIContext;

// AVDOVIMetadata from libavutil/dovi_meta.h (public).
// Try framework-style include first, fall back to bare header.
#if __has_include(<Libavutil/dovi_meta.h>)
#include <Libavutil/dovi_meta.h>
#elif __has_include(<libavutil/dovi_meta.h>)
#include <libavutil/dovi_meta.h>
#else
#include <dovi_meta.h>
#endif

/// Allocate and initialize a DOVIContext.
/// Wraps ff_dovi_ctx_alloc + ff_dovi_ctx_init (FFmpeg private API).
/// Returns NULL on allocation failure.
DOVIContext *ks_dovi_ctx_alloc(void);

/// Free a DOVIContext allocated by ks_dovi_ctx_alloc.
/// Wraps ff_dovi_ctx_free (FFmpeg private API).
void ks_dovi_ctx_free(DOVIContext *ctx);

/// Flush/reset DOVIContext parser state (e.g. on seek).
/// Wraps ff_dovi_ctx_flush (FFmpeg private API).
void ks_dovi_ctx_flush(DOVIContext *ctx);

/// Parse a raw DV RPU bitstream (after EPB removal) through the DOVIContext.
/// Returns 0 on success, negative on failure.
/// RE: Wraps ff_dovi_rpu_parse(ctx, data, size, 0) at binary 0x10140608c.
/// This is step 1 of the binary's Phase 2 chain -- parse only, no extraction.
int ks_dovi_rpu_parse(DOVIContext *ctx,
                      const uint8_t *data,
                      size_t size);

/// Extract the parsed AVDOVIMetadata from a DOVIContext after a successful
/// ks_dovi_rpu_parse call. Returns a pointer owned by the context (valid
/// until the next parse or free), or NULL if no metadata is available.
/// RE: Wraps FUN_102402568 (dovi_rpu_get_header) at binary 0x102402568.
/// This is step 2 of the binary's Phase 2 chain -- extraction after parse.
/// The caller should use av_dovi_get_header/mapping/color on the returned
/// pointer to extract the sub-structures.
const AVDOVIMetadata *ks_dovi_get_metadata(DOVIContext *ctx);

#endif /* DOVI_RPU_SHIM_H */
