/* &desc: "Declares dependency-free shared helpers used everywhere: the growable SBuf string builder, UTF-8 display-width and visible-character counting, and the PERMISSIONS/SIZE/DATE/hash-hex formatting functions." */
/* util.h -- small, dependency-free helpers shared by every module:
 * a growable string builder (used for JSON), UTF-8 column-width
 * counting (used for alignment), and formatting for the new
 * PERMISSIONS/SIZE/DATE columns. Nothing in here touches the
 * filesystem or the Node tree -- pure text/byte plumbing. */
#ifndef LTREE_UTIL_H
#define LTREE_UTIL_H

#include <stddef.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <stdint.h>

/* ===================== growable string builder ===================== */
typedef struct {
    char   *data;
    size_t  len;
    size_t  cap;
} SBuf;

void sbuf_init(SBuf *s);
void sbuf_ensure(SBuf *s, size_t extra);
void sbuf_append(SBuf *s, const char *str);
void sbuf_append_n(SBuf *s, const char *data, size_t n);
void sbuf_appendf(SBuf *s, const char *fmt, ...);
void sbuf_free(SBuf *s);
void sbuf_append_json_string(SBuf *s, const char *str);

/* ===================== UTF-8 aware display width ===================== */
size_t utf8_width(const char *s);

/* Counts "visible characters" over `size` raw bytes, for the CHARS
 * module/JSON field. Decodes real UTF-8 codepoints (rejecting
 * invalid/overlong/surrogate sequences instead of just counting lead
 * bytes like utf8_width does for column alignment), then skips
 * codepoints that never render as their own glyph -- combining marks,
 * variation selectors, zero-width joiners -- and counts an emoji flag
 * (two regional-indicator codepoints) as the single flag it displays
 * as. Not full UAX #29 grapheme-cluster segmentation (this project
 * carries no Unicode property database, see docs/architecture.md),
 * but meaningfully closer to "what a human would call one character"
 * than raw codepoint counting. */
long utf8_count_visible_chars(const unsigned char *data, size_t size);

/* ===================== formatting helpers ===================== */

/* "-rw-r--r--" style 10-char (+NUL) permission string. buf must be >= 11. */
void mode_string(mode_t mode, bool is_dir, bool is_symlink, char *buf);

/* Human size like "4.5K", "128b", "1.2G". buf must be >= 16. */
void human_size(int64_t bytes, char *buf, size_t bufsize);

/* Local-time "dd-mm-yyyy hh:mm:ss" formatting. buf must be >= 20. */
void format_datetime_local(time_t t, char *buf, size_t bufsize);

/* Local-time "dd-mm-yyyy_hh:mm:ss" for --save-output filenames. */
void format_timestamp_filename(time_t t, char *buf, size_t bufsize);

/* hex-encode `len` bytes of `hash` into `out` (out must be len*2+1). */
void hex_encode(const uint8_t *hash, size_t len, char *out);

/* decode a hex string (as produced by hex_encode) back into bytes.
 * returns number of bytes decoded, or 0 on malformed input. */
size_t hex_decode(const char *hex, uint8_t *out, size_t out_cap);

#endif
