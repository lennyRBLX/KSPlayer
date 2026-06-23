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
//  RE references (Forward 1.3.15, image base 0x100000000):
//    TrackDecode.md L704-714 (Phase 2 DV RPU parsing chain)
//    ff_dovi_rpu_parse      — definition @ 0x1024027d0; call site (the address
//                             the RE notes anchor) @ 0x10140608c.
//    ff_dovi_get_metadata   — @ 0x102402568. The RE notes mislabel this
//                             "dovi_rpu_get_header"; no such symbol exists in
//                             FFmpeg. The address realizes
//                             `int ff_dovi_get_metadata(DOVIContext*, AVDOVIMetadata**)`.
//    convertAVDOVIToKSDOVIMetadata — @ 0x10150c0a4 (KS-side serializer that
//                             flattens the AVDOVIMetadata into the 3008-byte
//                             KSDOVIMetadata GPU buffer; previously mislabeled
//                             "dovi_metadata_serialize"). Caller responsibility,
//                             not part of this shim.
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

/// Allocate and zero-initialize a caller-owned DOVIContext.
/// FFmpeg 8.x removed the heap-owning `ff_dovi_ctx_alloc` / `ff_dovi_ctx_free`
/// lifecycle; the modern contract is a caller-provided zeroed buffer that
/// `ff_dovi_rpu_parse` populates and `ff_dovi_ctx_unref` releases. This wraps
/// `calloc` to provide that buffer. Returns NULL on allocation failure.
DOVIContext *ks_dovi_ctx_alloc(void);

/// Free a DOVIContext allocated by ks_dovi_ctx_alloc.
/// Releases FFmpeg's internal allocations via ff_dovi_ctx_unref, then frees
/// the caller-owned buffer.
void ks_dovi_ctx_free(DOVIContext *ctx);

/// Flush/reset DOVIContext per-frame parser state (e.g. on seek), preserving
/// the stream-wide configuration record. Wraps ff_dovi_ctx_flush.
/// Note: ff_dovi_ctx_flush is exported by FFmpegKit's static libavcodec (nm: T)
/// — the Forward 1.3.15 binary inlined/LTO-eliminated it into ff_dovi_rpu_parse,
/// so it has no discrete address there, but it is a legitimate linkable symbol
/// against this project's FFmpegKit dependency.
void ks_dovi_ctx_flush(DOVIContext *ctx);

/// Parse a raw DV RPU bitstream (after EPB removal) through the DOVIContext.
/// Returns 0 on success, negative on failure.
/// RE: Wraps ff_dovi_rpu_parse(ctx, data, size, 0). The FFmpeg function is
/// defined at binary 0x1024027d0; Forward's per-frame call site is 0x10140608c.
/// This is step 1 of the binary's Phase 2 chain -- parse only, no extraction.
int ks_dovi_rpu_parse(DOVIContext *ctx,
                      const uint8_t *data,
                      size_t size);

/// Extract the decoded combined AVDOVIMetadata after a successful
/// ks_dovi_rpu_parse. Wraps ff_dovi_get_metadata(ctx, &out), which allocates
/// and assembles a fresh AVDOVIMetadata (header + mapping + color + extension
/// blocks) via av_dovi_metadata_alloc.
///
/// On success writes the newly allocated struct to *out_metadata and returns
/// its size (> 0); returns 0 if no metadata is available, or a negative AVERROR
/// on failure. **Ownership of *out_metadata passes to the caller** — release it
/// with ks_dovi_metadata_free. Use av_dovi_get_header/mapping/color on the
/// returned pointer to read the sub-structures.
///
/// RE: step 2 of the Phase 2 chain. Forward calls FUN_102402568(ctx, &outPtr)
/// @ 0x102402568 = ff_dovi_get_metadata. (Earlier notes mislabeled this
/// "dovi_rpu_get_header" and read ctx->dm directly at the wrong offset/type;
/// ctx->dm is a private AVDOVIColorMetadata*, not the combined metadata.)
int ks_dovi_get_metadata(DOVIContext *ctx, AVDOVIMetadata **out_metadata);

/// Free an AVDOVIMetadata returned by ks_dovi_get_metadata. The struct is a
/// single av_dovi_metadata_alloc'd flat buffer, so this wraps av_free.
void ks_dovi_metadata_free(AVDOVIMetadata *metadata);

#endif /* DOVI_RPU_SHIM_H */
