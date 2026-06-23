//
//  dovi_rpu_shim.c
//  KSPlayer — DOVIRPUShim
//
//  C shim implementation bridging FFmpeg's private DV RPU parser APIs
//  into a safe interface for Swift.
//
//  RE: TrackDecode.md L704-714 documents the binary's Phase 2 chain:
//    ff_dovi_rpu_parse(ctx, buf, outPos, 0)
//    size = FUN_102402568(ctx, &outPtr)             // ff_dovi_get_metadata
//    serialized = FUN_10150c0a4(outPtr)             // convertAVDOVIToKSDOVIMetadata (KS serializer)
//    memmove(tempBuf, serialized, 0xBC0)            // 3008 bytes
//    memcpy(self+0x50, tempBuf, 0xBC0)
//  Steps 1 (parse) and 2 (get_metadata) are wrapped here; the serialize +
//  stage steps (FUN_10150c0a4 / convertAVDOVIToKSDOVIMetadata) live on the
//  Swift side in the decode loop.
//
//  This shim re-declares the private function prototypes and lets the
//  linker resolve them against the statically linked Libavcodec/Libavutil.
//

#include "dovi_rpu_shim.h"
#include <stdlib.h>

// ── Private FFmpeg API declarations ──
// Defined in libavcodec/dovi_rpu.h (not shipped in FFmpegKit public headers);
// the symbols exist in the Libavcodec/Libavutil static archives (verified via
// `nm`: ff_dovi_ctx_unref, ff_dovi_ctx_flush, ff_dovi_rpu_parse,
// ff_dovi_get_metadata are T in Libavcodec; av_free is T in Libavutil).
//
// API NOTE (FFmpeg 8.x):
//   The old `ff_dovi_ctx_alloc` / `ff_dovi_ctx_free` heap-owning lifecycle
//   was removed upstream. The current lifecycle is:
//     1. Caller owns the `DOVIContext` storage (zero-initialized).
//     2. `ff_dovi_ctx_unref(ctx)` releases internal allocations (`dm`, `vdr`,
//        `ext_blocks`, `rpu_buf`); the struct itself stays usable.
//     3. To "free" entirely: call `ff_dovi_ctx_unref` then `free()` the buffer.
//
// Signatures (libavcodec/dovi_rpu.h):
//   void ff_dovi_ctx_unref(DOVIContext *s);                                  // full reset
//   void ff_dovi_ctx_flush(DOVIContext *s);                                  // per-frame/seek reset
//   int  ff_dovi_rpu_parse(DOVIContext *s, const uint8_t *rpu, size_t sz, int err_recognition);
//   int  ff_dovi_get_metadata(DOVIContext *s, AVDOVIMetadata **out_metadata);// caller owns *out
extern void ff_dovi_ctx_unref(DOVIContext *ctx);
extern void ff_dovi_ctx_flush(DOVIContext *ctx);
extern int ff_dovi_rpu_parse(DOVIContext *ctx, const uint8_t *rpu, size_t rpu_size, int err_recognition);
extern int ff_dovi_get_metadata(DOVIContext *ctx, AVDOVIMetadata **out_metadata);
extern void av_free(void *ptr);

// Caller-owned `DOVIContext` size. The FFmpeg struct is opaque to us; this
// constant is a generous upper bound large enough to fit any reasonable
// `DOVIContext` layout in FFmpeg 8.x (it embeds the inline `cfg` and `header`
// records plus a 16-wide `vdr` pointer array — a few hundred bytes — well under
// this bound). All bytes are zero-initialized so `ff_dovi_ctx_unref` against an
// unused context is a safe no-op (it only `av_freep`s nullable internal pointers).
#define KS_DOVI_CTX_SIZE 4096

DOVIContext *ks_dovi_ctx_alloc(void) {
    // Caller-owned storage, zero-initialized. `calloc` gives both zero-init and
    // a heap pointer matching the prior shim contract; FFmpeg 8.x removed the
    // `ff_dovi_ctx_alloc` heap-owning helper (it no longer exists to call).
    return (DOVIContext *)calloc(1, KS_DOVI_CTX_SIZE);
}

void ks_dovi_ctx_free(DOVIContext *ctx) {
    if (ctx) {
        // Release internal allocations first, then free the caller-owned buffer.
        // `ff_dovi_ctx_unref` against a still-empty context is a documented no-op.
        ff_dovi_ctx_unref(ctx);
        free(ctx);
    }
}

void ks_dovi_ctx_flush(DOVIContext *ctx) {
    if (ctx) {
        ff_dovi_ctx_flush(ctx);
    }
}

int ks_dovi_rpu_parse(DOVIContext *ctx,
                      const uint8_t *data,
                      size_t size) {
    if (!ctx || !data || size == 0) {
        return -1;
    }

    // RE: ff_dovi_rpu_parse(self.doviContext, buf, outPos, 0)
    // The 4th arg is err_recognition (0 = lenient).
    return ff_dovi_rpu_parse(ctx, data, size, 0);
}

int ks_dovi_get_metadata(DOVIContext *ctx, AVDOVIMetadata **out_metadata) {
    if (!ctx || !out_metadata) {
        return -1;
    }
    *out_metadata = NULL;

    // RE: FUN_102402568 @ 0x102402568 = ff_dovi_get_metadata. It calls
    // av_dovi_metadata_alloc and assembles a fresh combined AVDOVIMetadata
    // (header + mapping + color + extension blocks) into *out_metadata,
    // returning its size (> 0), 0 if none, or a negative AVERROR. Ownership of
    // *out_metadata passes to the caller (free with ks_dovi_metadata_free).
    //
    // The previous implementation read ctx->dm directly at +0x08: that offset
    // is the `enable` int (not a pointer), and ctx->dm is an
    // AVDOVIColorMetadata* (color-only), so the old path was UB and the wrong
    // type. Always go through ff_dovi_get_metadata.
    return ff_dovi_get_metadata(ctx, out_metadata);
}

void ks_dovi_metadata_free(AVDOVIMetadata *metadata) {
    // AVDOVIMetadata is a single av_dovi_metadata_alloc'd flat buffer; the
    // sub-structs live at internal offsets within it, so one av_free suffices.
    av_free(metadata);
}
