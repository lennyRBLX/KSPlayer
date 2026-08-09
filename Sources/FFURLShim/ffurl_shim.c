//
//  ffurl_shim.c
//  KSPlayer — FFURLShim
//
//  The header is the deliverable: it re-declares libavformat's private url.h surface so
//  Swift can name `URLContext` and call `ffurl_*`, and the linker resolves those symbols
//  against the statically linked libavformat. There is no wrapper code to write — unlike
//  DOVIRPUShim, nothing here needs a lifecycle helper, because the ffurl_* API already
//  owns its own allocation (ffurl_open_whitelist / ffurl_closep).
//
//  What this file DOES carry is the drift guard.
//

#include "ffurl_shim.h"

// ── Layout guard (deterministic, compile-time) ──
// The reconstruction stores `UnsafeMutablePointer<__C.URLContext>?` and reads fields BY
// NAME, so a layout change in a future FFmpegKit bump must fail the build rather than
// silently retype the field. 96 is not a hand-computed number: it is the output of
// compiling a probe against the real FFmpeg-n8.1.1/libavformat/url.h with this build's
// generated headers on the include path.
//   sizeof(URLContext) = 96, sizeof(AVIOInterruptCB) = 16
//   av_class 0 · prot 8 · priv_data 16 · filename 24 · flags 32 · max_packet_size 36
//   is_streamed 40 · is_connected 44 · interrupt_callback 48 · rw_timeout 64
//   protocol_whitelist 72 · protocol_blacklist 80 · min_packet_size 88
_Static_assert(sizeof(URLContext) == 96,
               "URLContext must be 96 B — reproduced from FFmpeg-n8.1.1/libavformat/url.h");
_Static_assert(sizeof(AVIOInterruptCB) == 16,
               "AVIOInterruptCB must be 16 B — URLContext's layout depends on it");
