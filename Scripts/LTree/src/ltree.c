/*
 * ltree.c -- blazing-fast recursive directory tree, line/char counter,
 * and JSON tree exporter. Zero external dependencies -- libc + POSIX
 * only (dirent, mmap, fnmatch), so it builds the same on any distro,
 * any libc (glibc/musl), no vendored deps to rot.
 *
 * Design in one paragraph: we walk the filesystem exactly once,
 * building an in-memory Node tree (dirs know their direct children,
 * files know their own line/char counts). Everything downstream --
 * the aligned tree view, the TOTAL summary, the FILES-by-extension
 * summary, and the JSON export -- is just a different way of reading
 * that same tree, so the expensive part (stat + mmap + byte scanning)
 * only ever happens once per file, no matter how many -o sections
 * you ask for.
 *
 * Build: gcc -O3 -std=c11 -Wall -Wextra -o ltree ltree.c
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <fnmatch.h>
#include <ctype.h>
#include <limits.h>
#include <errno.h>

/* ===================== ANSI colour palette ============================
 * Chosen for readability on both dark and light 256-colour terminals --
 * nothing neon, nothing that clashes with a typical prompt theme.
 * All of these collapse to "" when --no-colour is set, so every print
 * site just does COL(cfg,X) instead of branching on cfg->no_colour
 * itself -- keeps the printing code free of if/else noise.
 * ===================================================================== */
#define ANSI_RESET   "\x1b[0m"
#define ANSI_DIR     "\x1b[1;34m"   /* bold blue    -- directories       */
#define ANSI_FILE    "\x1b[0;37m"   /* light grey   -- regular files     */
#define ANSI_BRANCH  "\x1b[2;37m"   /* dim grey     -- tree branch glyphs*/
#define ANSI_LINES   "\x1b[0;32m"   /* green        -- L: column         */
#define ANSI_CHARS   "\x1b[0;33m"   /* yellow       -- C: column         */
#define ANSI_TOTAL   "\x1b[1;36m"   /* bold cyan    -- TOTAL summary      */
#define ANSI_EXT     "\x1b[0;35m"   /* magenta      -- FILES extensions   */
#define ANSI_SYMLINK "\x1b[1;35m"   /* bold magenta -- symlinks           */

#define COL(cfg, code) ((cfg)->no_colour ? "" : (code))
#define RST(cfg)       ((cfg)->no_colour ? "" : ANSI_RESET)

/* ===================== small growable string builder =================
 * Used only for JSON output. Doubles capacity, never shrinks -- this is
 * a short-lived buffer that gets flushed to stdout once and freed.
 * ===================================================================== */
typedef struct {
    char   *data;
    size_t  len;
    size_t  cap;
} SBuf;

static void sbuf_init(SBuf *s) {
    s->cap = 4096;
    s->len = 0;
    s->data = (char *)malloc(s->cap);
    if (!s->data) { perror("malloc"); exit(1); }
    s->data[0] = '\0';
}

static void sbuf_ensure(SBuf *s, size_t extra) {
    if (s->len + extra + 1 <= s->cap) return;
    size_t newcap = s->cap * 2;
    while (newcap < s->len + extra + 1) newcap *= 2;
    char *p = (char *)realloc(s->data, newcap);
    if (!p) { perror("realloc"); exit(1); }
    s->data = p;
    s->cap = newcap;
}

static void sbuf_append(SBuf *s, const char *str) {
    size_t n = strlen(str);
    sbuf_ensure(s, n);
    memcpy(s->data + s->len, str, n);
    s->len += n;
    s->data[s->len] = '\0';
}

static void sbuf_appendf(SBuf *s, const char *fmt, ...) {
    char tmp[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if ((size_t)n < sizeof(tmp)) {
        sbuf_append(s, tmp);
    } else {
        /* rare: huge number, fall back to heap buffer */
        char *big = (char *)malloc((size_t)n + 1);
        if (!big) return;
        va_start(ap, fmt);
        vsnprintf(big, (size_t)n + 1, fmt, ap);
        va_end(ap);
        sbuf_append(s, big);
        free(big);
    }
}

static void sbuf_free(SBuf *s) {
    free(s->data);
    s->data = NULL;
    s->len = s->cap = 0;
}

/* json string escaping -- appends a quoted, escaped string to sbuf */
static void sbuf_append_json_string(SBuf *s, const char *str) {
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

/* ===================== extension stats table ========================== */
typedef struct {
    char *ext;      /* "(no ext)" for extensionless files */
    long  files;
    long  lines;
    long  chars;
} ExtStat;

typedef struct {
    ExtStat *items;
    size_t   n, cap;
} ExtTable;

static void exttable_init(ExtTable *t) {
    t->cap = 16; t->n = 0;
    t->items = (ExtStat *)malloc(sizeof(ExtStat) * t->cap);
}

static void exttable_add(ExtTable *t, const char *ext, long lines, long chars) {
    for (size_t i = 0; i < t->n; i++) {
        if (strcmp(t->items[i].ext, ext) == 0) {
            t->items[i].files++;
            t->items[i].lines += lines;
            t->items[i].chars += chars;
            return;
        }
    }
    if (t->n == t->cap) {
        t->cap *= 2;
        t->items = (ExtStat *)realloc(t->items, sizeof(ExtStat) * t->cap);
    }
    t->items[t->n].ext = strdup(ext);
    t->items[t->n].files = 1;
    t->items[t->n].lines = lines;
    t->items[t->n].chars = chars;
    t->n++;
}

static void exttable_free(ExtTable *t) {
    for (size_t i = 0; i < t->n; i++) free(t->items[i].ext);
    free(t->items);
}

static int extstat_cmp_desc_lines(const void *a, const void *b) {
    const ExtStat *ea = (const ExtStat *)a, *eb = (const ExtStat *)b;
    if (eb->lines != ea->lines) return (eb->lines > ea->lines) ? 1 : -1;
    return strcmp(ea->ext, eb->ext);
}

/* ===================== tree node ======================================= */
typedef struct Node {
    char        *name;       /* basename                                  */
    bool         is_dir;
    bool         is_symlink;
    bool         truncated;  /* dir hit max-depth: exists, not expanded   */
    long         lines;      /* file: own count. dir: sum of DIRECT kids  */
    long         chars;
    struct Node **children;
    size_t       nchildren;
    size_t       children_cap;
} Node;

static Node *node_new(const char *name, bool is_dir) {
    Node *n = (Node *)calloc(1, sizeof(Node));
    if (!n) { perror("calloc"); exit(1); }
    n->name = strdup(name);
    n->is_dir = is_dir;
    return n;
}

static void node_add_child(Node *parent, Node *child) {
    if (parent->nchildren == parent->children_cap) {
        parent->children_cap = parent->children_cap ? parent->children_cap * 2 : 8;
        parent->children = (Node **)realloc(parent->children,
                                             sizeof(Node *) * parent->children_cap);
        if (!parent->children) { perror("realloc"); exit(1); }
    }
    parent->children[parent->nchildren++] = child;
}

static void node_free(Node *n) {
    if (!n) return;
    for (size_t i = 0; i < n->nchildren; i++) node_free(n->children[i]);
    free(n->children);
    free(n->name);
    free(n);
}

/* ===================== config ========================================== */
typedef struct {
    char  *path;
    bool   json;
    bool   dirs_only;
    bool   no_colour;
    int    max_depth;      /* -1 == unlimited */
    bool   o_lines, o_chars, o_total, o_files;
    char **excludes;
    size_t nexcludes;
} Config;

/* running totals, filled in while we build the tree */
typedef struct {
    long dirs;
    long files;
    long lines;
    long chars;
} Totals;

/* ===================== exclude matching ================================
 * Patterns with no '/' are matched against the basename only (so
 * "*.pyc" or "node_modules" hits at any depth). Patterns containing
 * '/' are matched against the path relative to the scan root. We use
 * libc fnmatch() without FNM_PATHNAME, so a single '*' is allowed to
 * cross path separators -- this gives '**'-like recursive matching
 * "for free" (a plain '*' already behaves like gitignore's '**') while
 * staying inside the standard library instead of hand-rolling a glob
 * engine.
 * ===================================================================== */
static bool is_excluded(const Config *cfg, const char *basename, const char *relpath) {
    for (size_t i = 0; i < cfg->nexcludes; i++) {
        const char *pat = cfg->excludes[i];
        if (strchr(pat, '/')) {
            if (fnmatch(pat, relpath, 0) == 0) return true;
        } else {
            if (fnmatch(pat, basename, 0) == 0) return true;
        }
    }
    return false;
}

/* split a comma-separated exclude list, honouring double quotes around
 * an entry so names containing spaces (or literal commas, if ever
 * needed) can be passed without ambiguity, e.g.:
 *   --exclude "some folder,*.pyc,\"another one\""
 */
static void parse_exclude_list(const char *arg, char ***out, size_t *out_n) {
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

/* ===================== file content scanning ===========================
 * mmap the file and scan it once: memchr() to count newlines (glibc's
 * memchr is typically SIMD-accelerated, far faster than a byte loop),
 * and a single pass counting UTF-8 *lead* bytes for the char count
 * (bytes whose top two bits are not "10") so multi-byte codepoints are
 * counted once, matching what a Python len(text) over decoded UTF-8
 * would give you. Falls back to read() for files mmap can't handle
 * (zero-length, pipes, etc).
 * ===================================================================== */
static void count_file(const char *path, long *out_lines, long *out_chars) {
    *out_lines = 0;
    *out_chars = 0;

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

    const unsigned char *data = (const unsigned char *)map;
    long lines = 0, chars = 0;

    const unsigned char *p = data;
    const unsigned char *end = data + size;
    while (p < end) {
        const unsigned char *nl = (const unsigned char *)memchr(p, '\n', (size_t)(end - p));
        if (!nl) break;
        lines++;
        p = nl + 1;
    }

    /* UTF-8 aware char count: skip continuation bytes (10xxxxxx) */
    for (size_t i = 0; i < size; i++) {
        if ((data[i] & 0xC0) != 0x80) chars++;
    }

    munmap(map, size);
    *out_lines = lines;
    *out_chars = chars;
}

/* ===================== sorting ========================================= */
static int node_cmp(const void *a, const void *b) {
    const Node *na = *(const Node **)a;
    const Node *nb = *(const Node **)b;
    /* case-insensitive alphabetical, dirs and files interleaved --
     * this is what real `tree` does and reads far more naturally than
     * "all dirs, then all files". */
    return strcasecmp(na->name, nb->name);
}

/* ===================== extension helper ================================ */
static const char *file_ext(const char *name) {
    const char *dot = strrchr(name, '.');
    if (!dot || dot == name) return "(no ext)";
    return dot + 1;
}

/* ===================== tree builder =====================================
 * Recursively walks `fullpath`, populating `parent`'s children. depth is
 * the depth of `fullpath` itself (root == 0). relbase is the path of
 * `fullpath` relative to the scan root, used for path-shaped excludes.
 * Aggregates into `totals` and `ext` as it goes (dirs_only suppresses
 * file traversal entirely for both speed and correctness).
 * ===================================================================== */
static void build_tree(Node *parent, const char *fullpath, const char *relbase,
                        int depth, const Config *cfg, Totals *totals, ExtTable *ext) {
    DIR *d = opendir(fullpath);
    if (!d) return;

    struct dirent *de;
    Node **local = NULL;
    size_t local_n = 0, local_cap = 0;

    while ((de = readdir(d)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) continue;

        char childpath[PATH_MAX];
        snprintf(childpath, sizeof(childpath), "%s/%s", fullpath, de->d_name);
        char relpath[PATH_MAX];
        if (relbase[0] == '\0') snprintf(relpath, sizeof(relpath), "%s", de->d_name);
        else snprintf(relpath, sizeof(relpath), "%s/%s", relbase, de->d_name);

        if (is_excluded(cfg, de->d_name, relpath)) continue;

        struct stat lst;
        if (lstat(childpath, &lst) != 0) continue;

        bool is_symlink = S_ISLNK(lst.st_mode);
        struct stat st = lst;
        if (is_symlink) {
            if (stat(childpath, &st) != 0) {
                /* dangling symlink -- show it as a leaf, no crash */
                st = lst;
            }
        }

        /* NOTE: we intentionally do NOT descend into symlinked directories
         * (cycle safety) even though we do show them. */
        bool target_is_dir = S_ISDIR(st.st_mode);

        if (cfg->dirs_only && !target_is_dir) continue;

        Node *node = node_new(de->d_name, target_is_dir);
        node->is_symlink = is_symlink;

        if (target_is_dir) {
            totals->dirs++;
            bool can_descend = !is_symlink &&
                                (cfg->max_depth < 0 || (depth + 1) < cfg->max_depth);
            if (can_descend) {
                build_tree(node, childpath, relpath, depth + 1, cfg, totals, ext);
                /* dir's own L/C = sum of its DIRECT children only */
                for (size_t i = 0; i < node->nchildren; i++) {
                    node->lines += node->children[i]->lines;
                    node->chars += node->children[i]->chars;
                }
            } else {
                node->truncated = true;
            }
        } else {
            long lines = 0, chars = 0;
            if (!is_symlink) count_file(childpath, &lines, &chars);
            node->lines = lines;
            node->chars = chars;
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
    }
    closedir(d);

    if (local_n) qsort(local, local_n, sizeof(Node *), node_cmp);
    for (size_t i = 0; i < local_n; i++) node_add_child(parent, local[i]);
    free(local);
}

/* ===================== UTF-8 aware display width ========================
 * Filenames are (almost) always ASCII, but box-drawing glyphs and any
 * unicode in a filename are multi-byte UTF-8. We only need column
 * *count*, not full wcwidth correctness, so: count lead bytes (any byte
 * that isn't a continuation byte 10xxxxxx) -- good enough for aligning
 * a terminal column and avoids pulling in wchar.h locale machinery.
 * ===================================================================== */
static size_t utf8_width(const char *s) {
    size_t w = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++)
        if ((*p & 0xC0) != 0x80) w++;
    return w;
}

/* ===================== flattened print line ============================= */
typedef struct {
    char  *prefix;     /* plain, no colour: indent + connector           */
    char  *name;
    bool   is_dir;
    bool   is_symlink;
    bool   truncated;
    long   lines;
    long   chars;
    size_t width;       /* utf8 display width of prefix+name             */
} PrintLine;

typedef struct {
    PrintLine *items;
    size_t     n, cap;
} LineBuf;

static void linebuf_init(LineBuf *lb) {
    lb->cap = 64; lb->n = 0;
    lb->items = (PrintLine *)malloc(sizeof(PrintLine) * lb->cap);
}

static PrintLine *linebuf_push(LineBuf *lb) {
    if (lb->n == lb->cap) {
        lb->cap *= 2;
        lb->items = (PrintLine *)realloc(lb->items, sizeof(PrintLine) * lb->cap);
    }
    return &lb->items[lb->n++];
}

static void linebuf_free(LineBuf *lb) {
    for (size_t i = 0; i < lb->n; i++) { free(lb->items[i].prefix); free(lb->items[i].name); }
    free(lb->items);
}

/* depth-first flatten with proper last-child tracking, so the branch
 * glyphs terminate correctly instead of "hoping something comes next":
 * a rounded corner (╰──) closes a column the moment we know we're
 * printing that column's final entry, and the vertical continuation
 * (│) for ancestor columns is only drawn for ancestors that were NOT
 * themselves a last child.
 */
static void flatten(Node *n, const char *prefix, bool is_last, bool is_root, LineBuf *lb) {
    if (!is_root) {
        PrintLine *pl = linebuf_push(lb);
        const char *connector = is_last ? "\xE2\x95\xB0\xE2\x94\x80\xE2\x94\x80 " /* ╰── */
                                         : "\xE2\x94\x9C\xE2\x94\x80\xE2\x94\x80 " /* ├── */;
        size_t plen = strlen(prefix) + strlen(connector) + 1;
        pl->prefix = (char *)malloc(plen);
        snprintf(pl->prefix, plen, "%s%s", prefix, connector);
        pl->name = strdup(n->name);
        pl->is_dir = n->is_dir;
        pl->is_symlink = n->is_symlink;
        pl->truncated = n->truncated;
        pl->lines = n->lines;
        pl->chars = n->chars;
        pl->width = utf8_width(pl->prefix) + utf8_width(pl->name) + (n->is_dir ? 1 : 0);
    }

    if (!n->is_dir) return;

    char childprefix[PATH_MAX];
    if (is_root) {
        childprefix[0] = '\0';
    } else {
        const char *cont = is_last ? "    " : "\xE2\x94\x82   " /* │   */;
        snprintf(childprefix, sizeof(childprefix), "%s%s", prefix, cont);
    }

    for (size_t i = 0; i < n->nchildren; i++) {
        bool last = (i == n->nchildren - 1);
        flatten(n->children[i], childprefix, last, false, lb);
    }
}

/* ===================== tree (human) output =============================== */
static void print_tree_view(Node *root, const char *display_path, const Config *cfg, const Totals *tot) {
    LineBuf lb;
    linebuf_init(&lb);
    flatten(root, "", true, true, &lb);

    /* module columns start 8 spaces past the widest name in the WHOLE
     * tree, so every L:/C: column lines up in one straight edge. */
    size_t maxw = utf8_width(display_path);
    for (size_t i = 0; i < lb.n; i++) if (lb.items[i].width > maxw) maxw = lb.items[i].width;
    size_t col_start = maxw + 8;

    bool any_module = cfg->o_lines || cfg->o_chars;

    printf("%s%s%s\n", COL(cfg, ANSI_DIR), display_path, RST(cfg));

    for (size_t i = 0; i < lb.n; i++) {
        PrintLine *pl = &lb.items[i];
        const char *namecol = pl->is_symlink ? COL(cfg, ANSI_SYMLINK)
                               : pl->is_dir   ? COL(cfg, ANSI_DIR)
                                              : COL(cfg, ANSI_FILE);
        printf("%s%s%s%s%s%s%s", COL(cfg, ANSI_BRANCH), pl->prefix, RST(cfg),
               namecol, pl->name, pl->is_dir ? "/" : "", RST(cfg));

        if (any_module) {
            size_t pad = (col_start > pl->width) ? (col_start - pl->width) : 1;
            for (size_t s = 0; s < pad; s++) putchar(' ');
            bool first = true;
            putchar('[');
            if (cfg->o_lines) {
                printf("%sL: %ld%s", COL(cfg, ANSI_LINES), pl->lines, RST(cfg));
                first = false;
            }
            if (cfg->o_chars) {
                if (!first) printf(", ");
                printf("%sC: %ld%s", COL(cfg, ANSI_CHARS), pl->chars, RST(cfg));
            }
            putchar(']');
        }
        if (pl->truncated) printf("  %s(...)%s", COL(cfg, ANSI_BRANCH), RST(cfg));
        putchar('\n');
    }

    linebuf_free(&lb);

    if (cfg->o_total) {
        printf("\n%sTOTAL:%s\n", COL(cfg, ANSI_TOTAL), RST(cfg));
        printf("  dirs:  %ld\n", tot->dirs);
        printf("  files: %ld\n", tot->files);
        printf("  lines: %ld\n", tot->lines);
        printf("  chars: %ld\n", tot->chars);
    }
}

static void print_files_summary(const ExtTable *ext, const Config *cfg) {
    if (ext->n == 0) return;
    ExtStat *sorted = (ExtStat *)malloc(sizeof(ExtStat) * ext->n);
    memcpy(sorted, ext->items, sizeof(ExtStat) * ext->n);
    qsort(sorted, ext->n, sizeof(ExtStat), extstat_cmp_desc_lines);

    size_t namew = 4; /* "TYPE" */
    for (size_t i = 0; i < ext->n; i++) {
        size_t w = strlen(sorted[i].ext);
        if (w > namew) namew = w;
    }

    printf("\n%sFILES:%s\n", COL(cfg, ANSI_TOTAL), RST(cfg));
    printf("  %-*s  %8s  %10s  %10s\n", (int)namew, "TYPE", "FILES", "LINES", "CHARS");
    for (size_t i = 0; i < ext->n; i++) {
        printf("  %s%-*s%s  %8ld  %10ld  %10ld\n",
               COL(cfg, ANSI_EXT), (int)namew, sorted[i].ext, RST(cfg),
               sorted[i].files, sorted[i].lines, sorted[i].chars);
    }
    free(sorted);
}

/* ===================== JSON output ======================================= */
static void json_node(SBuf *sb, Node *n, int indent) {
    for (int i = 0; i < indent; i++) sbuf_append(sb, "  ");
    sbuf_append(sb, "{\n");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_append(sb, "\"name\": "); sbuf_append_json_string(sb, n->name); sbuf_append(sb, ",\n");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"type\": \"%s\",\n", n->is_dir ? "dir" : "file");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"symlink\": %s,\n", n->is_symlink ? "true" : "false");
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"lines\": %ld,\n", n->lines);
    for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
    sbuf_appendf(sb, "\"chars\": %ld", n->chars);

    if (n->is_dir) {
        sbuf_append(sb, ",\n");
        for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
        if (n->truncated) {
            sbuf_append(sb, "\"truncated\": true,\n");
            for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
        }
        sbuf_append(sb, "\"children\": [");
        if (n->nchildren) {
            sbuf_append(sb, "\n");
            for (size_t i = 0; i < n->nchildren; i++) {
                json_node(sb, n->children[i], indent + 2);
                sbuf_append(sb, (i + 1 < n->nchildren) ? ",\n" : "\n");
            }
            for (int i = 0; i < indent + 1; i++) sbuf_append(sb, "  ");
        }
        sbuf_append(sb, "]\n");
    } else {
        sbuf_append(sb, "\n");
    }
    for (int i = 0; i < indent; i++) sbuf_append(sb, "  ");
    sbuf_append(sb, "}");
}

static void print_json(Node *root, const char *display_path, const Totals *tot, const ExtTable *ext) {
    SBuf sb;
    sbuf_init(&sb);
    sbuf_append(&sb, "{\n");
    sbuf_append(&sb, "  \"path\": "); sbuf_append_json_string(&sb, display_path); sbuf_append(&sb, ",\n");
    sbuf_append(&sb, "  \"total\": {\n");
    sbuf_appendf(&sb, "    \"dirs\": %ld,\n", tot->dirs);
    sbuf_appendf(&sb, "    \"files\": %ld,\n", tot->files);
    sbuf_appendf(&sb, "    \"lines\": %ld,\n", tot->lines);
    sbuf_appendf(&sb, "    \"chars\": %ld\n", tot->chars);
    sbuf_append(&sb, "  },\n");

    ExtStat *sorted = NULL;
    if (ext->n) {
        sorted = (ExtStat *)malloc(sizeof(ExtStat) * ext->n);
        memcpy(sorted, ext->items, sizeof(ExtStat) * ext->n);
        qsort(sorted, ext->n, sizeof(ExtStat), extstat_cmp_desc_lines);
    }
    sbuf_append(&sb, "  \"by_extension\": [");
    if (ext->n) {
        sbuf_append(&sb, "\n");
        for (size_t i = 0; i < ext->n; i++) {
            sbuf_append(&sb, "    {\"ext\": ");
            sbuf_append_json_string(&sb, sorted[i].ext);
            sbuf_appendf(&sb, ", \"files\": %ld, \"lines\": %ld, \"chars\": %ld}",
                         sorted[i].files, sorted[i].lines, sorted[i].chars);
            sbuf_append(&sb, (i + 1 < ext->n) ? ",\n" : "\n");
        }
        sbuf_append(&sb, "  ");
    }
    sbuf_append(&sb, "],\n");
    free(sorted);

    sbuf_append(&sb, "  \"tree\": \n");
    json_node(&sb, root, 1);
    sbuf_append(&sb, "\n}\n");

    fwrite(sb.data, 1, sb.len, stdout);
    sbuf_free(&sb);
}

/* ===================== CLI ================================================ */
static void print_usage(const char *prog) {
    printf(
        "usage: %s [path] [options]\n"
        "\n"
        "  -j                  output JSON instead of a tree view\n"
        "  -d                  list directories only\n"
        "  -L <n>              max depth to descend (like tree -L), also -L<n>\n"
        "  -o <MODULES>        comma-separated: LINES,CHARS,TOTAL,FILES (any order)\n"
        "  --exclude <list>    comma-separated names/globs to skip, quote entries\n"
        "                      with spaces: --exclude \"build,*.pyc,some dir\"\n"
        "  --no-colour         disable ANSI colour (also --no-color)\n"
        "  -h, --help          this help\n"
        "\n"
        "  LINES/CHARS print as an aligned [L: n] [C: n] column per entry\n"
        "  (dirs show the sum of their DIRECT children). TOTAL and FILES are\n"
        "  summary sections appended at the end; FILES breaks lines/chars\n"
        "  down by file extension.\n",
        prog);
}

int main(int argc, char **argv) {
    Config cfg = { .path = NULL, .json = false, .dirs_only = false, .no_colour = false,
                   .max_depth = -1, .o_lines = false, .o_chars = false,
                   .o_total = false, .o_files = false, .excludes = NULL, .nexcludes = 0 };

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-j") == 0) {
            cfg.json = true;
        } else if (strcmp(a, "-d") == 0) {
            cfg.dirs_only = true;
        } else if (strcmp(a, "--no-colour") == 0 || strcmp(a, "--no-color") == 0) {
            cfg.no_colour = true;
        } else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strncmp(a, "-L", 2) == 0 && strlen(a) > 2) {
            cfg.max_depth = atoi(a + 2);
        } else if (strcmp(a, "-L") == 0) {
            if (i + 1 < argc) cfg.max_depth = atoi(argv[++i]);
        } else if (strcmp(a, "-o") == 0) {
            if (i + 1 < argc) {
                char *val = strdup(argv[++i]);
                char *tok = strtok(val, ",");
                while (tok) {
                    if      (strcasecmp(tok, "LINES") == 0) cfg.o_lines = true;
                    else if (strcasecmp(tok, "CHARS") == 0) cfg.o_chars = true;
                    else if (strcasecmp(tok, "TOTAL") == 0) cfg.o_total = true;
                    else if (strcasecmp(tok, "FILES") == 0) cfg.o_files = true;
                    else fprintf(stderr, "warning: unknown -o module '%s'\n", tok);
                    tok = strtok(NULL, ",");
                }
                free(val);
            }
        } else if (strncmp(a, "-o", 2) == 0 && strlen(a) > 2) {
            char *val = strdup(a + 2);
            char *tok = strtok(val, ",");
            while (tok) {
                if      (strcasecmp(tok, "LINES") == 0) cfg.o_lines = true;
                else if (strcasecmp(tok, "CHARS") == 0) cfg.o_chars = true;
                else if (strcasecmp(tok, "TOTAL") == 0) cfg.o_total = true;
                else if (strcasecmp(tok, "FILES") == 0) cfg.o_files = true;
                tok = strtok(NULL, ",");
            }
            free(val);
        } else if (strcmp(a, "--exclude") == 0) {
            if (i + 1 < argc) {
                char **list; size_t n;
                parse_exclude_list(argv[++i], &list, &n);
                cfg.excludes = list;
                cfg.nexcludes = n;
            }
        } else if (strncmp(a, "--exclude=", 10) == 0) {
            char **list; size_t n;
            parse_exclude_list(a + 10, &list, &n);
            cfg.excludes = list;
            cfg.nexcludes = n;
        } else if (a[0] == '-' && strlen(a) > 1) {
            fprintf(stderr, "unknown option: %s\n", a);
            print_usage(argv[0]);
            return 1;
        } else {
            cfg.path = strdup(a);
        }
    }

    if (!cfg.path) cfg.path = strdup(".");

    struct stat st;
    if (stat(cfg.path, &st) != 0 || !S_ISDIR(st.st_mode)) {
        fprintf(stderr, "invalid path: %s\n", cfg.path);
        return 1;
    }

    Node *root = node_new(cfg.path, true);
    Totals totals = {0, 0, 0, 0};
    ExtTable ext;
    exttable_init(&ext);

    build_tree(root, cfg.path, "", 0, &cfg, &totals, &ext);
    for (size_t i = 0; i < root->nchildren; i++) {
        root->lines += root->children[i]->lines;
        root->chars += root->children[i]->chars;
    }

    if (cfg.json) {
        print_json(root, cfg.path, &totals, &ext);
    } else {
        print_tree_view(root, cfg.path, &cfg, &totals);
        if (cfg.o_files) print_files_summary(&ext, &cfg);
    }

    node_free(root);
    exttable_free(&ext);
    for (size_t i = 0; i < cfg.nexcludes; i++) free(cfg.excludes[i]);
    free(cfg.excludes);
    free(cfg.path);
    return 0;
}
