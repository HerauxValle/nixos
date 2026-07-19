/* &desc: "Implements the dependency-free SBuf string builder, UTF-8 display-width and visible-character counting, and the PERMISSIONS/SIZE/DATE/hash-hex formatting helpers." */
/* util.c -- see util.h. Kept dependency-free on purpose: this is the
 * one file that both the renderer and the JSON writer both pull in,
 * so it must never grow a dependency on Node, Config, or anything
 * that would make it circular. */
#define _GNU_SOURCE
#include "util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/ioctl.h>

/* ===================== growable string builder ===================== */
void sbuf_init(SBuf *s) {
    s->cap = 4096;
    s->len = 0;
    s->data = (char *)malloc(s->cap);
    if (!s->data) { perror("malloc"); exit(1); }
    s->data[0] = '\0';
}

void sbuf_ensure(SBuf *s, size_t extra) {
    if (s->len + extra + 1 <= s->cap) return;
    size_t newcap = s->cap * 2;
    while (newcap < s->len + extra + 1) newcap *= 2;
    char *p = (char *)realloc(s->data, newcap);
    if (!p) { perror("realloc"); exit(1); }
    s->data = p;
    s->cap = newcap;
}

void sbuf_append(SBuf *s, const char *str) {
    sbuf_append_n(s, str, strlen(str));
}

void sbuf_append_n(SBuf *s, const char *data, size_t n) {
    sbuf_ensure(s, n);
    memcpy(s->data + s->len, data, n);
    s->len += n;
    s->data[s->len] = '\0';
}

void sbuf_appendf(SBuf *s, const char *fmt, ...) {
    char tmp[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if ((size_t)n < sizeof(tmp)) {
        sbuf_append(s, tmp);
    } else {
        char *big = (char *)malloc((size_t)n + 1);
        if (!big) return;
        va_start(ap, fmt);
        vsnprintf(big, (size_t)n + 1, fmt, ap);
        va_end(ap);
        sbuf_append(s, big);
        free(big);
    }
}

void sbuf_free(SBuf *s) {
    free(s->data);
    s->data = NULL;
    s->len = s->cap = 0;
}

void sbuf_append_json_string(SBuf *s, const char *str) {
    sbuf_append(s, "\"");
    for (const unsigned char *p = (const unsigned char *)str; *p; p++) {
        switch (*p) {
            case '"':  sbuf_append(s, "\\\""); break;
            case '\\': sbuf_append(s, "\\\\"); break;
            case '\n': sbuf_append(s, "\\n");  break;
            case '\r': sbuf_append(s, "\\r");  break;
            case '\t': sbuf_append(s, "\\t");  break;
            default:
                if (*p < 0x20) sbuf_appendf(s, "\\u%04x", *p);
                else { char c[2] = { (char)*p, 0 }; sbuf_append(s, c); }
        }
    }
    sbuf_append(s, "\"");
}

/* ===================== UTF-8 aware display width ===================== */
size_t utf8_width(const char *s) {
    size_t w = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++)
        if ((*p & 0xC0) != 0x80) w++;
    return w;
}

/* Shared by render_ls.c's packed grid and columns.c's line-wrapping --
 * both need to know how wide a row can actually get
 * before something (the terminal's own raw column wrap, or our packed
 * grid) has to break it. $COLUMNS is the ioctl's documented fallback
 * for a non-tty/redirected stdout that still wants a sane width (a
 * pipe like `| less` sets it); 80 is the last-resort default every
 * terminal-width-dependent tool falls back to. */
size_t terminal_width(void) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) return ws.ws_col;
    const char *cols_env = getenv("COLUMNS");
    if (cols_env) {
        int c = atoi(cols_env);
        if (c > 0) return (size_t)c;
    }
    return 80;
}

/* ===================== precise "visible character" counting =========
 * See util.h for the rationale. Decodes one codepoint at a time,
 * rejecting malformed UTF-8 (a stray/invalid byte is skipped and not
 * counted, rather than inflating the total the way lead-byte counting
 * would), then applies two corrections on top of raw codepoint count:
 *   - combining marks / variation selectors / ZWJ / ZWNJ never count
 *     as their own character (they modify the glyph before them);
 *   - a pair of regional-indicator codepoints (an emoji flag) counts
 *     as one character, not two.
 * ===================================================================== */
static int utf8_decode_one(const unsigned char *p, size_t remaining, uint32_t *cp) {
    unsigned char c0 = p[0];
    if (c0 < 0x80) { *cp = c0; return 1; }

    int len; uint32_t min_cp, val;
    if      ((c0 & 0xE0) == 0xC0) { len = 2; min_cp = 0x80;    val = c0 & 0x1F; }
    else if ((c0 & 0xF0) == 0xE0) { len = 3; min_cp = 0x800;   val = c0 & 0x0F; }
    else if ((c0 & 0xF8) == 0xF0) { len = 4; min_cp = 0x10000; val = c0 & 0x07; }
    else return 0; /* stray continuation byte or an invalid lead byte */

    if ((size_t)len > remaining) return 0; /* truncated at end of buffer */
    for (int i = 1; i < len; i++) {
        if ((p[i] & 0xC0) != 0x80) return 0; /* not a continuation byte -- malformed */
        val = (val << 6) | (uint32_t)(p[i] & 0x3F);
    }
    /* reject overlong encodings and the surrogate/out-of-range codepoints
     * UTF-8 must never actually encode */
    if (val < min_cp || val > 0x10FFFF || (val >= 0xD800 && val <= 0xDFFF)) return 0;

    *cp = val;
    return len;
}

static bool utf8_is_non_spacing(uint32_t cp) {
    return (cp >= 0x0300  && cp <= 0x036F)   /* combining diacritical marks      */
        || (cp >= 0x1AB0  && cp <= 0x1AFF)   /* combining diacritical marks ext  */
        || (cp >= 0x1DC0  && cp <= 0x1DFF)   /* combining diacritical marks supp */
        || (cp >= 0x20D0  && cp <= 0x20FF)   /* combining diacritical marks sym  */
        || (cp >= 0xFE20  && cp <= 0xFE2F)   /* combining half marks             */
        || (cp >= 0xFE00  && cp <= 0xFE0F)   /* variation selectors              */
        || (cp >= 0xE0100 && cp <= 0xE01EF)  /* variation selectors supplement   */
        || cp == 0x200D                       /* zero-width joiner                */
        || cp == 0x200C;                       /* zero-width non-joiner            */
}

long utf8_count_visible_chars(const unsigned char *data, size_t size) {
    long count = 0;
    size_t i = 0;
    bool pending_regional = false; /* mid-way through a flag's 2-codepoint pair */

    while (i < size) {
        uint32_t cp;
        int len = utf8_decode_one(data + i, size - i, &cp);
        if (len == 0) { i++; continue; } /* malformed byte: skip, don't count */

        if (utf8_is_non_spacing(cp)) { i += (size_t)len; continue; }

        if (cp >= 0x1F1E6 && cp <= 0x1F1FF) { /* regional indicator symbol */
            if (pending_regional) pending_regional = false; /* 2nd half: already counted */
            else { count++; pending_regional = true; }
            i += (size_t)len;
            continue;
        }

        pending_regional = false;
        count++;
        i += (size_t)len;
    }
    return count;
}

/* ===================== permission string ===================== */
void mode_string(mode_t mode, bool is_dir, bool is_symlink, char *buf) {
    buf[0] = is_symlink ? 'l' : is_dir ? 'd' : '-';
    buf[1] = (mode & S_IRUSR) ? 'r' : '-';
    buf[2] = (mode & S_IWUSR) ? 'w' : '-';
    buf[3] = (mode & S_IXUSR) ? 'x' : '-';
    buf[4] = (mode & S_IRGRP) ? 'r' : '-';
    buf[5] = (mode & S_IWGRP) ? 'w' : '-';
    buf[6] = (mode & S_IXGRP) ? 'x' : '-';
    buf[7] = (mode & S_IROTH) ? 'r' : '-';
    buf[8] = (mode & S_IWOTH) ? 'w' : '-';
    buf[9] = (mode & S_IXOTH) ? 'x' : '-';
    buf[10] = '\0';
}

/* ===================== human size ===================== */
void human_size(int64_t bytes, char *buf, size_t bufsize) {
    if (bytes < 1024) {
        snprintf(buf, bufsize, "%lldb", (long long)bytes);
        return;
    }
    static const char *units = "KMGT";
    double val = (double)bytes / 1024.0;
    int ui = 0;
    while (val >= 1024.0 && ui < 3) { val /= 1024.0; ui++; }
    snprintf(buf, bufsize, "%.1f%c", val, units[ui]);
}

/* ===================== date/time formatting (local timezone) ========= */
void format_datetime_local(time_t t, char *buf, size_t bufsize) {
    struct tm tmv;
    localtime_r(&t, &tmv);
    snprintf(buf, bufsize, "%02d-%02d-%04d %02d:%02d:%02d",
              tmv.tm_mday, tmv.tm_mon + 1, tmv.tm_year + 1900,
              tmv.tm_hour, tmv.tm_min, tmv.tm_sec);
}

void format_timestamp_filename(time_t t, char *buf, size_t bufsize) {
    struct tm tmv;
    localtime_r(&t, &tmv);
    snprintf(buf, bufsize, "%02d-%02d-%04d_%02d:%02d:%02d",
              tmv.tm_mday, tmv.tm_mon + 1, tmv.tm_year + 1900,
              tmv.tm_hour, tmv.tm_min, tmv.tm_sec);
}

/* ===================== hex encode/decode ===================== */
static const char HEXCHARS[] = "0123456789abcdef";

void hex_encode(const uint8_t *hash, size_t len, char *out) {
    for (size_t i = 0; i < len; i++) {
        out[i * 2]     = HEXCHARS[(hash[i] >> 4) & 0xF];
        out[i * 2 + 1] = HEXCHARS[hash[i] & 0xF];
    }
    out[len * 2] = '\0';
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

size_t hex_decode(const char *hex, uint8_t *out, size_t out_cap) {
    size_t hlen = strlen(hex);
    if (hlen % 2 != 0) return 0;
    size_t n = hlen / 2;
    if (n > out_cap) return 0;
    for (size_t i = 0; i < n; i++) {
        int hi = hex_nibble(hex[i * 2]);
        int lo = hex_nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) return 0;
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return n;
}
