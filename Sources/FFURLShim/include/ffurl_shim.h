//
//  ffurl_shim.h
//  KSPlayer — FFURLShim
//
//  C shim exposing FFmpeg's private libavformat/url.h surface — the `URLContext`
//  type and the `ffurl_*` protocol-layer API — to Swift.
//
//  WHY THIS EXISTS
//  ---------------
//  Forward built against full FFmpeg sources, so its field records type
//  `URLContextDownload.context` as `UnsafeMutablePointer<__C.URLContext>?`. FFmpegKit
//  ships PUBLIC headers only: `FFmpeg/ios/thin/arm64/include/libavformat/` carries
//  avformat.h, avio.h, config.h, os_support.h, version.h and version_major.h — but not
//  url.h. The type was therefore unnameable in Swift and two derived bodies could not be
//  written at all:
//    PreLoadIOContext_download_existential
//    LimitSeparatePreLoadIOContext_more_idx30_101ba5398_s104
//  Session 116 fully derived `URLContextDownload.init(url:flags:options:interrupt:isReadComplete:)`
//  @0x101b90c58 before hitting that wall.
//
//  This follows the DOVIRPUShim precedent exactly: re-declare the private surface so the
//  linker resolves it against the statically linked archive. It does NOT patch the
//  xcframework, so an FFmpegKit rebuild cannot silently drop it.
//
//  LINKAGE IS VERIFIED, NOT ASSUMED. Every prototype below is defined (nm -g
//  --defined-only => T) in
//  FFmpegKit/.Script/FFmpeg/ios/thin/arm64/lib/libavformat.a. Declaring a private FFmpeg
//  function that the archive only REFERENCES (U) would compile and then fail to link.
//
//  LAYOUT IS COMPILER-DERIVED, NOT TRANSCRIBED. `URLContext` below is reproduced verbatim
//  from FFmpegKit/.Script/FFmpeg-n8.1.1/libavformat/url.h — the same source tree that
//  produced this build's archives, per the project rule to read layouts from the build
//  headers and never assume a version. sizeof and every field offset were obtained by
//  compiling a probe against that real header (sizeof == 96); the .c carries the size as a
//  _Static_assert so an FFmpegKit bump fails the build instead of drifting silently.
//
//  Note the two spellings the API actually uses: the read/write/seek entry points take
//  `void *urlcontext`, not `URLContext *` — `ffurl_seek` is a static inline wrapper that
//  never survives as a call target, and the real export is `ffurl_seek2`.
//

#ifndef FFURL_SHIM_H
#define FFURL_SHIM_H

#include <stdint.h>

// Public FFmpeg headers this surface depends on. url.h itself includes exactly these three
// (avio.h, libavutil/dict.h, libavutil/log.h) and nothing else — there is no internal-header
// cascade. Framework-style include first, matching DOVIRPUShim.
#if __has_include(<Libavformat/avio.h>)
#include <Libavformat/avio.h>
#else
#include <libavformat/avio.h>
#endif

#if __has_include(<Libavutil/dict.h>)
#include <Libavutil/dict.h>
#include <Libavutil/log.h>
#else
#include <libavutil/dict.h>
#include <libavutil/log.h>
#endif

// ── URLContext ──
// Verbatim from FFmpeg-n8.1.1/libavformat/url.h. Reproduced in full rather than held opaque
// (as DOVIRPUShim does for DOVIContext) because every member type here is public and
// available: AVClass from log.h, AVIOInterruptCB from avio.h. A full declaration lets a
// reconstructed body read a field BY NAME, which is the project rule; an opaque byte blob
// would force numeric offsets, which is forbidden.
typedef struct URLContext {
    const AVClass *av_class;    /**< information for av_log(). Set by url_open(). */
    const struct URLProtocol *prot;
    void *priv_data;
    char *filename;             /**< specified URL */
    int flags;
    int max_packet_size;        /**< if non zero, the stream is packetized with this max packet size */
    int is_streamed;            /**< true if streamed (no seek possible), default = false */
    int is_connected;
    AVIOInterruptCB interrupt_callback;
    int64_t rw_timeout;         /**< maximum time to wait for (network) read/write operation completion, in mcs */
    const char *protocol_whitelist;
    const char *protocol_blacklist;
    int min_packet_size;        /**< if non zero, the stream is packetized with this min packet size */
} URLContext;

// URLProtocol stays OPAQUE. `URLContext.prot` is a pointer to it and nothing in the
// reconstruction dereferences it; declaring its 20+ function-pointer members would add
// surface with no reader. Forward-declared only.
struct URLProtocol;
typedef struct URLProtocol URLProtocol;

// ── Private ffurl_* API (Swift-callable) ──
// Signatures verbatim from libavformat/url.h; each symbol verified T in libavformat.a.

int ffurl_alloc(URLContext **puc, const char *filename, int flags,
                const AVIOInterruptCB *int_cb);

int ffurl_connect(URLContext *uc, AVDictionary **options);

int ffurl_open_whitelist(URLContext **puc, const char *filename, int flags,
               const AVIOInterruptCB *int_cb, AVDictionary **options,
               const char *whitelist, const char* blacklist,
               URLContext *parent);

int ffurl_accept(URLContext *s, URLContext **c);
int ffurl_handshake(URLContext *c);

// urlcontext is `void *` upstream, not `URLContext *`. Kept as written.
int ffurl_read2(void *urlcontext, uint8_t *buf, int size);
int ffurl_write2(void *urlcontext, const uint8_t *buf, int size);
int64_t ffurl_seek2(void *urlcontext, int64_t pos, int whence);
int ffurl_get_short_seek(void *urlcontext);

int ffurl_read_complete(URLContext *h, unsigned char *buf, int size);
int ffurl_closep(URLContext **h);
int ffurl_close(URLContext *h);
int64_t ffurl_size(URLContext *h);
int ffurl_get_file_handle(URLContext *h);
int ffurl_get_multi_file_handle(URLContext *h, int **handles, int *numhandles);
int ffurl_shutdown(URLContext *h, int flags);
const URLProtocol **ffurl_get_protocols(const char *whitelist,
                                        const char *blacklist);
int ffurl_move(const char *url_src, const char *url_dst);
int ffurl_delete(const char *url);

#endif /* FFURL_SHIM_H */
