#define _GNU_SOURCE
#include "render_tree.h"
#include "colors.h"
#include "util.h"
#include "exttable.h"
#include "hash.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* how many bytes of a hash digest to show in the [H: ...] column --
 * full digests are for JSON/DIFF integrity, the terminal only needs
 * enough to eyeball "did this change". */
#define HASH_DISPLAY_BYTES 8

/* ===================== flattened print line ============================= */
typedef struct {
    char  *prefix;      /* plain, no colour: indent + connector           */
    char  *name;        /* possibly extension-stripped display name       */
    bool   is_dir;
    bool   is_symlink;
    bool   truncated;
    long   lines, chars;
    mode_t mode;
    int64_t size_bytes;
    time_t mtime;
    uint8_t hash[HASH_MAX_BYTES];
    uint8_t hash_len;
    bool   diff_checked;
    bool   modified;
    size_t width;        /* utf8 display width of prefix+name              */
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

static void flatten(Node *n, const Config *cfg, const char *prefix,
                     bool is_last, bool is_root, LineBuf *lb) {
    if (!is_root) {
        PrintLine *pl = linebuf_push(lb);
        const char *connector = is_last ? "\xE2\x95\xB0\xE2\x94\x80\xE2\x94\x80 " /* ╰── */
                                         : "\xE2\x94\x9C\xE2\x94\x80\xE2\x94\x80 " /* ├── */;
        size_t plen = strlen(prefix) + strlen(connector) + 1;
        pl->prefix = (char *)malloc(plen);
        snprintf(pl->prefix, plen, "%s%s", prefix, connector);

        if (!n->is_dir && !cfg->o_ext) pl->name = strip_ext_for_display(n->name);
        else                            pl->name = strdup(n->name);

        pl->is_dir = n->is_dir;
        pl->is_symlink = n->is_symlink;
        pl->truncated = n->truncated;
        pl->lines = n->lines;
        pl->chars = n->chars;
        pl->mode = n->mode;
        pl->size_bytes = n->size_bytes;
        pl->mtime = n->mtime;
        memcpy(pl->hash, n->hash, HASH_MAX_BYTES);
        pl->hash_len = n->hash_len;
        pl->diff_checked = n->diff_checked;
        pl->modified = n->modified;
        pl->width = utf8_width(pl->prefix) + utf8_width(pl->name) + (n->is_dir ? 1 : 0);
    }

    if (!n->is_dir) return;

    char childprefix[4096];
    if (is_root) {
        childprefix[0] = '\0';
    } else {
        const char *cont = is_last ? "    " : "\xE2\x94\x82   " /* │   */;
        snprintf(childprefix, sizeof(childprefix), "%s%s", prefix, cont);
    }

    for (size_t i = 0; i < n->nchildren; i++) {
        bool last = (i == n->nchildren - 1);
        flatten(n->children[i], cfg, childprefix, last, false, lb);
    }
}

/* ===================== module column rendering ===========================
 * Every active module gets its OWN bracket, in a fixed order
 * (L, C, P, S, D, H) regardless of the order they were passed to -o,
 * so output is stable. Two passes: first render every line's module
 * text (plain, no colour) and track each module's own max width, then
 * print with each bracket padded to its column's width before the
 * fixed 3-space gap to the next bracket. The [m] DIFF flag trails
 * after everything else and isn't column-aligned since it's boolean
 * and always the same short width when present.
 * ===================================================================== */
typedef enum { MOD_L, MOD_C, MOD_P, MOD_S, MOD_D, MOD_H, MOD_COUNT } ModuleId;

static bool module_active(const Config *cfg, ModuleId m) {
    switch (m) {
        case MOD_L: return cfg->o_lines;
        case MOD_C: return cfg->o_chars;
        case MOD_P: return cfg->o_perm;
        case MOD_S: return cfg->o_size;
        case MOD_D: return cfg->o_date;
        case MOD_H: return cfg->o_hash;
        default:    return false;
    }
}

static const char *module_color(const Config *cfg, ModuleId m) {
    switch (m) {
        case MOD_L: return COL(cfg, ANSI_LINES);
        case MOD_C: return COL(cfg, ANSI_CHARS);
        case MOD_P: return COL(cfg, ANSI_PERM);
        case MOD_S: return COL(cfg, ANSI_SIZE);
        case MOD_D: return COL(cfg, ANSI_DATE);
        case MOD_H: return COL(cfg, ANSI_HASH);
        default:    return "";
    }
}

static char *render_module_text(ModuleId m, const PrintLine *pl) {
    char buf[128];
    switch (m) {
        case MOD_L:
            snprintf(buf, sizeof(buf), "[L: %ld]", pl->lines);
            break;
        case MOD_C:
            snprintf(buf, sizeof(buf), "[C: %ld]", pl->chars);
            break;
        case MOD_P: {
            char modebuf[11];
            mode_string(pl->mode, pl->is_dir, pl->is_symlink, modebuf);
            snprintf(buf, sizeof(buf), "[P: %s]", modebuf);
            break;
        }
        case MOD_S: {
            char sizebuf[16];
            human_size(pl->size_bytes, sizebuf, sizeof(sizebuf));
            snprintf(buf, sizeof(buf), "[S: %s]", sizebuf);
            break;
        }
        case MOD_D: {
            char datebuf[32];
            format_datetime_local(pl->mtime, datebuf, sizeof(datebuf));
            snprintf(buf, sizeof(buf), "[D: %s]", datebuf);
            break;
        }
        case MOD_H: {
            if (pl->hash_len == 0) {
                snprintf(buf, sizeof(buf), "[H: -]");
            } else {
                uint8_t show = pl->hash_len < HASH_DISPLAY_BYTES ? pl->hash_len : HASH_DISPLAY_BYTES;
                char hex[HASH_DISPLAY_BYTES * 2 + 1];
                hex_encode(pl->hash, show, hex);
                snprintf(buf, sizeof(buf), "[H: %s]", hex);
            }
            break;
        }
        default:
            buf[0] = '\0';
    }
    return strdup(buf);
}

/* ===================== tree (human) output =============================== */
void print_tree_view(Node *root, const char *display_path, const Config *cfg,
                      const Totals *tot, bool diff_available, const DebugStats *dbg) {
    LineBuf lb;
    linebuf_init(&lb);
    flatten(root, cfg, "", true, true, &lb);

    size_t maxw = utf8_width(display_path);
    for (size_t i = 0; i < lb.n; i++) if (lb.items[i].width > maxw) maxw = lb.items[i].width;
    size_t col_start = maxw + 8;

    ModuleId order[MOD_COUNT] = { MOD_L, MOD_C, MOD_P, MOD_S, MOD_D, MOD_H };
    bool active[MOD_COUNT];
    size_t colwidth[MOD_COUNT];
    char **rendered[MOD_COUNT];
    bool any_module = false;

    for (int mi = 0; mi < MOD_COUNT; mi++) {
        ModuleId m = order[mi];
        active[mi] = module_active(cfg, m);
        colwidth[mi] = 0;
        rendered[mi] = NULL;
        if (!active[mi]) continue;
        any_module = true;
        rendered[mi] = (char **)malloc(sizeof(char *) * (lb.n ? lb.n : 1));
        for (size_t i = 0; i < lb.n; i++) {
            rendered[mi][i] = render_module_text(m, &lb.items[i]);
            size_t w = strlen(rendered[mi][i]);
            if (w > colwidth[mi]) colwidth[mi] = w;
        }
    }

    printf("%s%s%s\n", COL(cfg, ANSI_DIR), display_path, RST(cfg));

    for (size_t i = 0; i < lb.n; i++) {
        PrintLine *pl = &lb.items[i];
        bool is_mod = cfg->o_diff && pl->diff_checked && pl->modified;
        const char *namecol = is_mod                ? COL(cfg, ANSI_MODIFIED)
                               : pl->is_symlink       ? COL(cfg, ANSI_SYMLINK)
                               : pl->is_dir           ? COL(cfg, ANSI_DIR)
                                                       : COL(cfg, ANSI_FILE);
        printf("%s%s%s%s%s%s%s", COL(cfg, ANSI_BRANCH), pl->prefix, RST(cfg),
               namecol, pl->name, pl->is_dir ? "/" : "", RST(cfg));

        if (any_module) {
            size_t pad = (col_start > pl->width) ? (col_start - pl->width) : 1;
            for (size_t s = 0; s < pad; s++) putchar(' ');

            bool first = true;
            for (int mi = 0; mi < MOD_COUNT; mi++) {
                if (!active[mi]) continue;
                if (!first) printf("   ");
                first = false;
                const char *text = rendered[mi][i];
                printf("%s%s%s", module_color(cfg, order[mi]), text, RST(cfg));
                size_t pad2 = colwidth[mi] - strlen(text);
                for (size_t s = 0; s < pad2; s++) putchar(' ');
            }
            if (is_mod) {
                if (!first) printf("   ");
                printf("[m]");
            }
        }
        if (pl->truncated) printf("  %s(...)%s", COL(cfg, ANSI_BRANCH), RST(cfg));
        putchar('\n');
    }

    for (int mi = 0; mi < MOD_COUNT; mi++) {
        if (!active[mi]) continue;
        for (size_t i = 0; i < lb.n; i++) free(rendered[mi][i]);
        free(rendered[mi]);
    }
    linebuf_free(&lb);

    if (cfg->o_total) {
        printf("\n%sTOTAL:%s\n", COL(cfg, ANSI_TOTAL), RST(cfg));
        printf("  dirs:  %ld\n", tot->dirs);
        printf("  files: %ld\n", tot->files);
        printf("  lines: %ld\n", tot->lines);
        printf("  chars: %ld\n", tot->chars);
    }

    if (cfg->o_debug && dbg) {
        debug_print_text(dbg, cfg);
    }

    if (cfg->o_diff && !diff_available) {
        printf("\n%snote: no previous .ltree snapshot found, run again after --save-output"
               " to enable DIFF%s\n", COL(cfg, ANSI_NOTE), RST(cfg));
    }
}
