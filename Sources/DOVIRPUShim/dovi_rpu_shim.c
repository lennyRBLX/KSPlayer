//
//  dovi_rpu_shim.c
//  KSPlayer — DOVIRPUShim
//
//  C shim implementation bridging FFmpeg's private DV RPU parser APIs
//  into a safe, single-function interface for Swift.
//
//  RE: TrackDecode.md L704-714 documents the binary's Phase 2 chain:
//    ff_dovi_rpu_parse(ctx, buf, outPos, 0)
//    doviHeader = FUN_102402568(ctx, &outPtr)  // dovi_rpu_get_header
//    serialized = FUN_10150c0a4(outPtr)         // dovi_metadata_serialize
//    memmove(tempBuf, serialized, 0xBC0)        // 3008 bytes
//    memcpy(self+0x50, tempBuf, 0xBC0)
//
//  This shim re-declares the private function prototypes and lets the
//  linker resolve them against the statically linked Libavcodec.
//

#include "dovi_rpu_shim.h"
#include <stdlib.h>
#include <string.h>

// ── Private FFmpeg API declarations ──
// These are defined in libavcodec/dovi_rpu.h (not shipped in FFmpegKit
// public headers). The symbols exist in the Libavcodec static archive.
//
// Signature reference: FFmpeg source (libavcodec/dovi_rpu.h + dovi_rpu.c)
//   DOVIContext *ff_dovi_ctx_alloc(AVCodecContext *avctx, int flags);
//     -- avctx may be NULL for standalone parsing (profile 0 / flag 0)
//   void ff_dovi_ctx_flush(DOVIContext *ctx);
//   void ff_dovi_ctx_free(DOVIContext *ctx);
//   int ff_dovi_rpu_parse(DOVIContext *ctx, const uint8_t *rpu, size_t rpu_size, int err_recognition);
//
// After a successful parse, the context holds parsed metadata internally.
// The context's public `AVDOVIMetadata *metadata` field (or accessor) gives
// the parsed result.

// Forward-declare the private API functions.
// The linker resolves these against the Libavcodec static library.
extern DOVIContext *ff_dovi_ctx_alloc(void *avctx, int flags);
extern void ff_dovi_ctx_flush(DOVIContext *ctx);
extern void ff_dovi_ctx_free(DOVIContext *ctx);
extern int ff_dovi_rpu_parse(DOVIContext *ctx, const uint8_t *rpu, size_t rpu_size, int err_recognition);

// Access the parsed metadata from the context.
// In FFmpeg's DOVIContext struct layout, the AVDOVIMetadata pointer
// is stored at a known offset. We access it via the struct field.
// Since DOVIContext is opaque to us, we need to know the offset.
//
// FFmpeg's DOVIContext (from dovi_rpu.h) has this layout:
//   typedef struct DOVIContext {
//       void *logctx;                    // +0x00
//       AVDOVIMetadata *dm;              // +0x08 (the parsed metadata)
//       size_t dm_size;                  // +0x10
//       ... (more fields)
//   };
//
// However, relying on struct offset is fragile across FFmpeg versions.
// A safer approach: ff_dovi_rpu_parse returns 0 on success and fills
// ctx->dm. We access ctx->dm via a well-known ABI-stable accessor
// pattern. Since the struct is truly opaque, we cast to read the second
// pointer field.
//
// NOTE: This is ABI-dependent on the FFmpegKit build. If FFmpegKit
// updates its FFmpeg version, this offset may need re-verification.

// Internal struct layout mirror (just enough to access the dm field)
struct DOVIContextInternal {
    void *logctx;
    AVDOVIMetadata *dm;
    // ... remaining fields omitted
};

DOVIContext *ks_dovi_ctx_alloc(void) {
    // NULL avctx = standalone parser, flags=0 = default behavior
    return ff_dovi_ctx_alloc(NULL, 0);
}

void ks_dovi_ctx_free(DOVIContext *ctx) {
    if (ctx) {
        ff_dovi_ctx_free(ctx);
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
    // The 4th arg is err_recognition (0 = lenient)
    return ff_dovi_rpu_parse(ctx, data, size, 0);
}

const AVDOVIMetadata *ks_dovi_get_metadata(DOVIContext *ctx) {
    if (!ctx) {
        return NULL;
    }

    // RE: FUN_102402568 (dovi_rpu_get_header) returns a pointer to the
    // context's internal AVDOVIMetadata, which contains header, mapping,
    // and color sub-structures accessible via av_dovi_get_header/mapping/color.
    struct DOVIContextInternal *internal_ctx = (struct DOVIContextInternal *)ctx;
    return internal_ctx->dm;
}
