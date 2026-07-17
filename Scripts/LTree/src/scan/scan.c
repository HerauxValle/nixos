/* &desc: "Implements build_tree, the one recursive filesystem walk (exclude/gitignore/-o HIDDEN filtering, per-file mmap+memchr line/char/hash/DESC-marker scanning, --simple-hash sampling, statx birth-time fetch) with three streaming hooks interleaved into the recursion, wired up only when --live is passed, so -o TREE can print top-down as it goes." */
#define _GNU_SOURCE
#include "scan/scan.h"
#include "util/util.h"
#include "util/spinner.h"
#include "core/modules.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <fnmatch.h>
#include <limits.h>
#include <signal.h>
#include <setjmp.h>

/* ===================== mmap fault guard =================================
 * Pseudo-files under /proc and /sys report a size via stat() that has
 * nothing to do with real, safely-mappable memory -- e.g. a sysfs PCI
 * "resourceN" file is a raw MMIO window; touching certain offsets of
 * its mmap with memchr()/a byte scan can raise SIGBUS/SIGSEGV/SIGILL
 * depending on the device and kernel, not because of a bug in this
 * program. Rather than special-casing every pseudo-filesystem by magic
 * number (fragile, kernel-version-dependent), we scope a signal
 * handler tightly around the one risky operation (touching the mapped
 * bytes) and treat a fault there as "this file's content can't be
 * safely read" -- 0 lines/chars, no hash -- instead of taking the
 * whole scan down. The handler is installed and torn down around each
 * call, and re-raises anything it wasn't expecting (so a real crash
 * elsewhere in the program still crashes normally, not silently). */
static sigjmp_buf g_scan_fault_jmp;
static volatile sig_atomic_t g_scan_fault_armed = 0;

static void scan_fault_handler(int sig) {
    if (g_scan_fault_armed) siglongjmp(g_scan_fault_jmp, 1);
    /* Not something we armed for -- restore default behaviour and
     * re-raise, so it terminates/cores the normal way. */
    signal(sig, SIG_DFL);
    raise(sig);
}

/* Runs work_fn(map, size, ctx) with SIGSEGV/SIGBUS/SIGILL guarded.
 * Returns false if a fault interrupted work_fn (map may only be
 * partially processed -- caller must not trust partial output). */
static bool scan_guarded(void (*work_fn)(const void *, size_t, void *),
                          const void *map, size_t size, void *ctx) {
    struct sigaction sa, old_segv, old_bus, old_ill;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = scan_fault_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, &old_segv);
    sigaction(SIGBUS, &sa, &old_bus);
    sigaction(SIGILL, &sa, &old_ill);

    g_scan_fault_armed = 1;
    bool faulted = (sigsetjmp(g_scan_fault_jmp, 1) != 0);
    if (!faulted) work_fn(map, size, ctx);
    g_scan_fault_armed = 0;

    sigaction(SIGSEGV, &old_segv, NULL);
    sigaction(SIGBUS, &old_bus, NULL);
    sigaction(SIGILL, &old_ill, NULL);
    return !faulted;
}

/* ===================== exclude matching ================================
 * Patterns with no '/' are matched against the basename only (so
 * "*.pyc" or "node_modules" hits at any depth). Patterns containing
 * '/' are matched against the path relative to the scan root. We use
 * libc fnmatch() without FNM_PATHNAME, so a single '*' is allowed to
 * cross path separators. --gitignore patterns (if enabled) are
 * consulted on top of --exclude -- either one can exclude a path.
 * ===================================================================== */
static bool is_excluded(const Config *cfg, const GitTable *gt,
                         const char *basename, const char *relpath, bool is_dir) {
    /* .ltree is our own snapshot store (see save.c / diff.c), never
     * user content -- always hidden from the walk, same way most tools
     * hide .git, so --save-output snapshots don't get scanned, counted,
     * and diffed against themselves on the next run. This is
     * unconditional, regardless of -o HIDDEN below. */
    if (is_dir && strcmp(basename, ".ltree") == 0) return true;

    /* Dotfiles/dot-dirs are hidden from the walk unless -o HIDDEN was
     * requested -- off by default, like `ls` without `-a` (see
     * docs/plan-ls-rework.md, Category 3). This is a scan-level
     * exclusion, so it applies the same way to every output mode
     * (ls view, tree view, JSON). */
    if (!cfg->modules[MOD_HIDDEN] && basename[0] == '.') return true;

    for (size_t i = 0; i < cfg->nexcludes; i++) {
        const char *pat = cfg->excludes[i];
        if (strchr(pat, '/')) {
            if (fnmatch(pat, relpath, 0) == 0) return true;
        } else {
            if (fnmatch(pat, basename, 0) == 0) return true;
        }
    }
    if (gt && gitignore_is_excluded(gt, basename, relpath, is_dir)) return true;
    return false;
}

/* split a comma-separated exclude list, honouring double quotes around
 * an entry so names containing spaces can be passed unambiguously. */
void parse_exclude_list(const char *arg, char ***out, size_t *out_n) {
    size_t cap = 8, n = 0;
    char **list = (char **)malloc(sizeof(char *) * cap);
    size_t len = strlen(arg);
    size_t i = 0;
    while (i < len) {
        char buf[PATH_MAX];
        size_t bi = 0;
        bool quoted = false;
        if (arg[i] == '"') { quoted = true; i++; }
        while (i < len) {
            if (quoted) {
                if (arg[i] == '"') { i++; break; }
            } else {
                if (arg[i] == ',') break;
            }
            if (bi < sizeof(buf) - 1) buf[bi++] = arg[i];
            i++;
        }
        buf[bi] = '\0';
        if (i < len && arg[i] == ',') i++;
        if (bi > 0) {
            if (n == cap) { cap *= 2; list = (char **)realloc(list, sizeof(char *) * cap); }
            list[n++] = strdup(buf);
        }
    }
    *out = list;
    *out_n = n;
}

/* ===================== unified content scan =============================
 * mmap the file ONCE and, in a single linear pass: memchr() to count
 * newlines, a lead-byte pass for UTF-8 char count, and (if requested)
 * feed the same mapped region into hash_compute(). Whichever subset of
 * {lines, chars, hash} is actually needed, this is still exactly one
 * open+fstat+mmap+munmap per file -- no second I/O pass for hashing.
 * The actual byte-touching work runs under scan_guarded() (see above)
 * since some regular-looking files (sysfs MMIO windows, some /proc
 * entries) can fault mid-read for reasons outside this program's
 * control.
 * ===================================================================== */
typedef struct {
    HashAlgo    algo;
    bool        need_hash;
    bool        simple_hash;
    bool        need_desc;
    const char *desc_prefix;
    const char *desc_suffix;
    long        lines, chars;
    uint8_t     hash[HASH_MAX_BYTES];
    uint8_t     hash_len;
    char       *desc;
} ScanWork;

/* ===================== -o DESC marker search ==============================
 * Bounded, not exhaustive: this project's own `&desc: "..."` header
 * comments always sit at the very top of a file, so only the first
 * DESC_SEARCH_WINDOW bytes are searched for the prefix, and the closing
 * suffix is only looked for within DESC_MAX_LEN bytes after it -- past
 * that, treat it as "no description" rather than scanning arbitrarily far
 * into a large file just to rule one out (ASSUMPTION -- see
 * docs/plan-hash-desc-spinner.md). Only the first match is used; returns
 * a malloc'd string, or NULL if nothing matched within those bounds. */
#define DESC_SEARCH_WINDOW (64u * 1024u)
#define DESC_MAX_LEN 4096u

static char *desc_search(const unsigned char *data, size_t size,
                          const char *prefix, const char *suffix) {
    size_t prefix_len = strlen(prefix);
    size_t suffix_len = strlen(suffix);
    size_t window = size < DESC_SEARCH_WINDOW ? size : DESC_SEARCH_WINDOW;
    if (window < prefix_len) return NULL;

    const void *hit = memmem(data, window, prefix, prefix_len);
    if (!hit) return NULL;

    const unsigned char *value_start = (const unsigned char *)hit + prefix_len;
    size_t remaining = size - (size_t)(value_start - data);
    size_t scan_len = remaining < DESC_MAX_LEN ? remaining : DESC_MAX_LEN;
    if (scan_len < suffix_len) return NULL;

    const void *end_hit = memmem(value_start, scan_len, suffix, suffix_len);
    if (!end_hit) return NULL;

    size_t desc_len = (size_t)((const unsigned char *)end_hit - value_start);
    return strndup((const char *)value_start, desc_len);
}

/* ===================== --simple-hash sampling ===========================
 * Below SIMPLE_HASH_THRESHOLD, sampling wouldn't save anything -- hash the
 * whole file exactly like the default. Above it, hash a small fixed
 * buffer built from the file ([size as 8 bytes][first 64KiB][last 64KiB])
 * instead of every byte -- same hash_compute() dispatch either way, so
 * this works unchanged for both xxhash64 and --cryptographic's sha256.
 * Since the file is already mmap'd, only the touched head/tail pages ever
 * actually get read off disk -- that's the real I/O win on large files, on
 * top of not running the hash's compression function over the whole
 * thing. `g_simple_hash_scratch` is static/reused rather than
 * malloc'd per call -- this is a single-threaded, one-scan-per-process
 * tool (same convention as render_tree.c's g_depth statics). */
#define SIMPLE_HASH_CHUNK 65536u
#define SIMPLE_HASH_THRESHOLD (SIMPLE_HASH_CHUNK * 2u)
static uint8_t g_simple_hash_scratch[8 + SIMPLE_HASH_CHUNK * 2];

static void hash_simple_or_full(HashAlgo algo, bool simple, const unsigned char *data,
                                 size_t size, uint8_t out[HASH_MAX_BYTES], uint8_t *out_len) {
    if (!simple || size <= SIMPLE_HASH_THRESHOLD) {
        hash_compute(algo, data, size, out, out_len);
        return;
    }
    uint64_t size_le = (uint64_t)size; /* host is little-endian, see hash.c's file header note */
    memcpy(g_simple_hash_scratch, &size_le, 8);
    memcpy(g_simple_hash_scratch + 8, data, SIMPLE_HASH_CHUNK);
    memcpy(g_simple_hash_scratch + 8 + SIMPLE_HASH_CHUNK, data + size - SIMPLE_HASH_CHUNK,
           SIMPLE_HASH_CHUNK);
    hash_compute(algo, g_simple_hash_scratch, sizeof(g_simple_hash_scratch), out, out_len);
}

static void scan_file_content_work(const void *map, size_t size, void *ctx_) {
    ScanWork *ctx = (ScanWork *)ctx_;
    const unsigned char *data = (const unsigned char *)map;
    long lines = 0;

    const unsigned char *p = data;
    const unsigned char *end = data + size;
    while (p < end) {
        const unsigned char *nl = (const unsigned char *)memchr(p, '\n', (size_t)(end - p));
        if (!nl) break;
        lines++;
        p = nl + 1;
    }

    long chars = utf8_count_visible_chars(data, size);

    if (ctx->need_hash)
        hash_simple_or_full(ctx->algo, ctx->simple_hash, data, size, ctx->hash, &ctx->hash_len);

    if (ctx->need_desc)
        ctx->desc = desc_search(data, size, ctx->desc_prefix, ctx->desc_suffix);

    ctx->lines = lines;
    ctx->chars = chars;
}

static void scan_file_content(const char *path, HashAlgo algo, bool need_hash, bool simple_hash,
                               bool need_desc, const char *desc_prefix, const char *desc_suffix,
                               long *out_lines, long *out_chars,
                               uint8_t out_hash[HASH_MAX_BYTES], uint8_t *out_hash_len,
                               char **out_desc) {
    *out_lines = 0;
    *out_chars = 0;
    *out_hash_len = 0;
    *out_desc = NULL;

    int fd = open(path, O_RDONLY);
    if (fd < 0) return;

    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size == 0) {
        close(fd);
        return;
    }

    size_t size = (size_t)st.st_size;
    void *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED) return;
    madvise(map, size, MADV_SEQUENTIAL);

    ScanWork ctx = { .algo = algo, .need_hash = need_hash, .simple_hash = simple_hash,
                     .need_desc = need_desc, .desc_prefix = desc_prefix, .desc_suffix = desc_suffix,
                     .lines = 0, .chars = 0, .hash_len = 0, .desc = NULL };
    memset(ctx.hash, 0, HASH_MAX_BYTES);

    bool ok = scan_guarded(scan_file_content_work, map, size, &ctx);
    munmap(map, size);

    if (!ok) return; /* faulted mid-read -- leave *out_* as the zeroed "unreadable" state */

    *out_lines = ctx.lines;
    *out_chars = ctx.chars;
    memcpy(out_hash, ctx.hash, HASH_MAX_BYTES);
    *out_hash_len = ctx.hash_len;
    *out_desc = ctx.desc;
}

/* ===================== birth time (--sort birth) =========================
 * st_mtime is the only timestamp `struct stat` gives us; creation time
 * needs the newer statx() syscall with STATX_BTIME. Not every
 * filesystem/kernel actually reports one (btime support varies -- e.g.
 * some older filesystems have no birth-time field at all), so this
 * always follows symlinks to their target (statx with no
 * AT_SYMLINK_NOFOLLOW, mirroring how `st.st_mtime` above is already
 * resolved via stat() rather than lstat()) and falls back to the
 * already-resolved mtime whenever btime isn't available -- "unknown
 * creation time" silently degrading to "last known modification time"
 * is a far less surprising failure mode than a garbage/zero timestamp
 * for --sort birth. ===================================================== */
time_t fetch_btime(const char *path, time_t mtime_fallback) {
    struct statx stx;
    if (statx(AT_FDCWD, path, 0, STATX_BTIME, &stx) == 0 && (stx.stx_mask & STATX_BTIME)) {
        return (time_t)stx.stx_btime.tv_sec;
    }
    return mtime_fallback;
}

/* ===================== tree builder ===================================== */
void build_tree(Node *parent, const char *fullpath, const char *relbase,
                 int depth, const Config *cfg, const GitTable *gt,
                 Totals *totals, ExtTable *ext,
                 DirMeasureFn on_dir_measure, EntryReadyFn on_entry_ready,
                 DirDoneFn on_dir_done, void *ctx) {
    DIR *d = opendir(fullpath);
    if (!d) return;

    bool need_hash = (cfg->hash_algo != HASH_ALGO_NONE);

    struct dirent *de;
    Node **local = NULL;
    size_t local_n = 0, local_cap = 0;

    /* Phase 1: figure out every direct child (files fully scanned;
     * subdirectories created and marked truncated/not, but NOT
     * recursed into yet -- see the callback note below for why this
     * is now a separate phase from descending). */
    while ((de = readdir(d)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;

        char childpath[PATH_MAX];
        snprintf(childpath, sizeof(childpath), "%s/%s", fullpath, de->d_name);
        char relpath[PATH_MAX];
        if (relbase[0] == '\0') snprintf(relpath, sizeof(relpath), "%s", de->d_name);
        else snprintf(relpath, sizeof(relpath), "%s/%s", relbase, de->d_name);

        struct stat lst;
        if (lstat(childpath, &lst) != 0) continue;
        bool is_symlink = S_ISLNK(lst.st_mode);
        bool probe_is_dir = S_ISDIR(lst.st_mode);

        if (is_excluded(cfg, gt, de->d_name, relpath, probe_is_dir)) continue;

        struct stat st = lst;
        if (is_symlink) {
            if (stat(childpath, &st) != 0) st = lst; /* dangling symlink -- show as leaf */
        }

        /* NOTE: we intentionally do NOT descend into symlinked directories
         * (cycle safety) even though we do show them. */
        bool target_is_dir = S_ISDIR(st.st_mode);

        if (cfg->dirs_only && !target_is_dir) continue;

        Node *node = node_new(de->d_name, target_is_dir);
        node->is_symlink = is_symlink;
        node->mode = st.st_mode;
        node->mtime = st.st_mtime;
        node->btime = fetch_btime(childpath, st.st_mtime);

        if (target_is_dir) {
            totals->dirs++;
            bool can_descend = !is_symlink &&
                                (cfg->max_depth < 0 || (depth + 1) < cfg->max_depth);
            node->truncated = !can_descend;
        } else {
            long lines = 0, chars = 0;
            uint8_t hbuf[HASH_MAX_BYTES] = {0}; uint8_t hlen = 0;
            char *desc = NULL;
            if (!is_symlink) {
                scan_file_content(childpath, cfg->hash_algo, need_hash, cfg->simple_hash,
                                   cfg->need_desc, cfg->desc_prefix, cfg->desc_suffix,
                                   &lines, &chars, hbuf, &hlen, &desc);
            }
            node->lines = lines;
            node->chars = chars;
            node->size_bytes = st.st_size;
            memcpy(node->hash, hbuf, HASH_MAX_BYTES);
            node->hash_len = hlen;
            node->desc = desc;
            totals->files++;
            totals->lines += lines;
            totals->chars += chars;
            exttable_add(ext, file_ext(de->d_name), lines, chars);
        }

        if (local_n == local_cap) {
            local_cap = local_cap ? local_cap * 2 : 8;
            local = (Node **)realloc(local, sizeof(Node *) * local_cap);
        }
        local[local_n++] = node;
        spinner_tick(false); /* rate-limited -- see util/spinner.h */
    }
    closedir(d);

    if (local_n) qsort(local, local_n, sizeof(Node *), node_cmp);
    for (size_t i = 0; i < local_n; i++) node_add_child(parent, local[i]);
    free(local);

    /* `parent`'s own direct children are now fully known (files fully
     * scanned; subdirectories present but not yet expanded). Fire the
     * measure hook once, up front, so a streaming renderer can size
     * columns across all of `parent`'s children before printing any
     * of them (see render/render_tree.h) -- then print+recurse ONE
     * ENTRY AT A TIME, interleaved, so a subtree prints immediately
     * after its own directory's line instead of after all of that
     * directory's siblings (batching all of `parent`'s lines before
     * recursing into any of them produces the wrong shape entirely --
     * see docs/plan-ls-rework.md, Category 7, for why this replaced
     * an earlier "print all siblings, then recurse" attempt). */
    if (on_dir_measure) on_dir_measure(parent, depth, cfg, ctx);

    for (size_t i = 0; i < parent->nchildren; i++) {
        Node *node = parent->children[i];
        bool is_last = (i + 1 == parent->nchildren);

        if (on_entry_ready) on_entry_ready(node, i, is_last, depth + 1, cfg, ctx);

        if (node->is_dir && !node->truncated) {
            char childpath[PATH_MAX];
            snprintf(childpath, sizeof(childpath), "%s/%s", fullpath, node->name);
            char relpath[PATH_MAX];
            if (relbase[0] == '\0') snprintf(relpath, sizeof(relpath), "%s", node->name);
            else snprintf(relpath, sizeof(relpath), "%s/%s", relbase, node->name);

            build_tree(node, childpath, relpath, depth + 1, cfg, gt, totals, ext,
                       on_dir_measure, on_entry_ready, on_dir_done, ctx);

            for (size_t k = 0; k < node->nchildren; k++) {
                node->lines += node->children[k]->lines;
                node->chars += node->children[k]->chars;
                node->size_bytes += node->children[k]->size_bytes;
            }
            if (need_hash && node->nchildren > 0) {
                char **names = (char **)malloc(sizeof(char *) * node->nchildren);
                uint8_t (*hashes)[HASH_MAX_BYTES] =
                    malloc(sizeof(uint8_t[HASH_MAX_BYTES]) * node->nchildren);
                uint8_t *lens = (uint8_t *)malloc(node->nchildren);
                for (size_t k = 0; k < node->nchildren; k++) {
                    names[k] = node->children[k]->name;
                    memcpy(hashes[k], node->children[k]->hash, HASH_MAX_BYTES);
                    lens[k] = node->children[k]->hash_len;
                }
                hash_combine_children(cfg->hash_algo, names, hashes, lens,
                                       node->nchildren, node->hash, &node->hash_len);
                free(names); free(hashes); free(lens);
            }
        }
    }

    if (on_dir_done) on_dir_done(depth + 1, cfg, ctx);
}
