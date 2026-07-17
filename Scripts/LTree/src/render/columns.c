#define _GNU_SOURCE
#include "render/columns.h"
#include "render/colors.h"
#include "util/util.h"
#include "scan/exttable.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* how many bytes of a hash digest to show in the [H: ...] column --
 * full digests are for JSON/DIFF integrity, the terminal only needs
 * enough to eyeball "did this change". */
#define HASH_DISPLAY_BYTES 8

void linebuf_init(LineBuf *lb) {
    lb->cap = 64; lb->n = 0;
    lb->items = (PrintLine *)malloc(sizeof(PrintLine) * lb->cap);
}

PrintLine *linebuf_push(LineBuf *lb) {
    if (lb->n == lb->cap) {
        lb->cap *= 2;
        lb->items = (PrintLine *)realloc(lb->items, sizeof(PrintLine) * lb->cap);
    }
    return &lb->items[lb->n++];
}

void linebuf_free(LineBuf *lb) {
    for (size_t i = 0; i < lb->n; i++) { free(lb->items[i].prefix); free(lb->items[i].name); }
    free(lb->items);
}

void printline_fill(PrintLine *pl, Node *n, const Config *cfg) {
    if (!n->is_dir && !cfg->modules[MOD_EXT]) pl->name = strip_ext_for_display(n->name);
    else                                       pl->name = strdup(n->name);

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
}

const ModuleId RENDER_COLUMNS[RENDER_COLUMN_COUNT] = {
    MOD_LINES, MOD_CHARS, MOD_PERM, MOD_SIZE, MOD_DATE, MOD_HASH
};

static const char *module_color(const Config *cfg, ModuleId m) {
    switch (m) {
        case MOD_LINES: return COL(cfg, ANSI_LINES);
        case MOD_CHARS: return COL(cfg, ANSI_CHARS);
        case MOD_PERM:  return COL(cfg, ANSI_PERM);
        case MOD_SIZE:  return COL(cfg, ANSI_SIZE);
        case MOD_DATE:  return COL(cfg, ANSI_DATE);
        case MOD_HASH:  return COL(cfg, ANSI_HASH);
        default:        return "";
    }
}

static char *render_module_text(ModuleId m, const PrintLine *pl) {
    char buf[128];
    switch (m) {
        case MOD_LINES:
            snprintf(buf, sizeof(buf), "[L: %ld]", pl->lines);
            break;
        case MOD_CHARS:
            snprintf(buf, sizeof(buf), "[C: %ld]", pl->chars);
            break;
        case MOD_PERM: {
            char modebuf[11];
            mode_string(pl->mode, pl->is_dir, pl->is_symlink, modebuf);
            snprintf(buf, sizeof(buf), "[P: %s]", modebuf);
            break;
        }
        case MOD_SIZE: {
            char sizebuf[16];
            human_size(pl->size_bytes, sizebuf, sizeof(sizebuf));
            snprintf(buf, sizeof(buf), "[S: %s]", sizebuf);
            break;
        }
        case MOD_DATE: {
            char datebuf[32];
            format_datetime_local(pl->mtime, datebuf, sizeof(datebuf));
            snprintf(buf, sizeof(buf), "[D: %s]", datebuf);
            break;
        }
        case MOD_HASH: {
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

/* Fills mc->order[]: the fixed L/C/P/S/D/H order, unless -o ...,O asked
 * to respect -o argument order instead (see docs/plan-ls-rework.md,
 * Category 5). cfg->order_seen may also contain TOTAL/DEBUG/etc from
 * the same -o list (anything MODCAT_COLUMN or not) -- this filters
 * down to just the six column modules, in the order they were typed,
 * then appends whichever column modules weren't typed at all (in
 * fixed order) so all six always end up placed exactly once. */
static void resolve_column_order(const Config *cfg, ModuleId order[RENDER_COLUMN_COUNT]) {
    for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) order[mi] = RENDER_COLUMNS[mi];
    if (!cfg->o_order || cfg->n_order_seen == 0) return;

    bool placed[MOD_COUNT] = {0};
    int oi = 0;
    for (int i = 0; i < cfg->n_order_seen && oi < RENDER_COLUMN_COUNT; i++) {
        ModuleId id = cfg->order_seen[i];
        if (MODULE_TABLE[id].cat != MODCAT_COLUMN) continue;
        if (placed[id]) continue;
        order[oi++] = id;
        placed[id] = true;
    }
    for (int mi = 0; mi < RENDER_COLUMN_COUNT && oi < RENDER_COLUMN_COUNT; mi++) {
        ModuleId id = RENDER_COLUMNS[mi];
        if (placed[id]) continue;
        order[oi++] = id;
        placed[id] = true;
    }
}

void columns_measure(const LineBuf *lb, const Config *cfg, MeasuredColumns *mc) {
    mc->any_module = false;
    resolve_column_order(cfg, mc->order);
    for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
        ModuleId m = mc->order[mi];
        mc->active[mi] = cfg->modules[m];
        mc->colwidth[mi] = 0;
        mc->rendered[mi] = NULL;
        if (!mc->active[mi]) continue;
        mc->any_module = true;
        mc->rendered[mi] = (char **)malloc(sizeof(char *) * (lb->n ? lb->n : 1));
        for (size_t i = 0; i < lb->n; i++) {
            mc->rendered[mi][i] = render_module_text(m, &lb->items[i]);
            size_t w = strlen(mc->rendered[mi][i]);
            if (w > mc->colwidth[mi]) mc->colwidth[mi] = w;
        }
    }
}

void columns_free(const LineBuf *lb, MeasuredColumns *mc) {
    for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
        if (!mc->active[mi]) continue;
        for (size_t i = 0; i < lb->n; i++) free(mc->rendered[mi][i]);
        free(mc->rendered[mi]);
    }
}

/* "[L: 26]" -> "L:26" -- strips the brackets and the single space
 * render_module_text() always puts after the colon, for --condense's
 * tighter one-bracket-per-entry form. */
static void condense_field(const char *bracketed, char *out, size_t outsz) {
    size_t len = strlen(bracketed);
    if (len < 2) { out[0] = '\0'; return; }
    const char *inner = bracketed + 1;
    size_t inner_len = len - 2;
    size_t oi = 0;
    for (size_t i = 0; i < inner_len && oi + 1 < outsz; i++) {
        if (inner[i] == ':' && i + 1 < inner_len && inner[i + 1] == ' ') {
            out[oi++] = ':';
            i++;
            continue;
        }
        out[oi++] = inner[i];
    }
    out[oi] = '\0';
}

void columns_print_line(const MeasuredColumns *mc, const Config *cfg,
                         const PrintLine *pl, size_t i, size_t col_start) {
    bool is_mod = cfg->modules[MOD_DIFF] && pl->diff_checked && pl->modified;

    if (!mc->any_module && !is_mod) return;

    size_t pad = (col_start > pl->width) ? (col_start - pl->width) : 1;
    for (size_t s = 0; s < pad; s++) putchar(' ');

    /* --condense: one [L:x C:y ...] bracket instead of one bracket per
     * column, still colour-coded per field, no per-column width
     * padding inside it (that's the whole point -- tight, not
     * columnar). The [m] DIFF flag stays a separate trailing marker,
     * same as uncondensed -- it's a modification flag, not one of the
     * data columns condense is folding together. */
    if (cfg->condense && mc->any_module) {
        putchar('[');
        bool first = true;
        for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
            if (!mc->active[mi]) continue;
            if (!first) putchar(' ');
            first = false;
            char buf[128];
            condense_field(mc->rendered[mi][i], buf, sizeof(buf));
            printf("%s%s%s", module_color(cfg, mc->order[mi]), buf, RST(cfg));
        }
        putchar(']');
        if (is_mod) printf("   [m]");
        return;
    }

    bool first = true;
    for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
        if (!mc->active[mi]) continue;
        if (!first) printf("   ");
        first = false;
        const char *text = mc->rendered[mi][i];
        printf("%s%s%s", module_color(cfg, mc->order[mi]), text, RST(cfg));
        size_t pad2 = mc->colwidth[mi] - strlen(text);
        for (size_t s = 0; s < pad2; s++) putchar(' ');
    }
    if (is_mod) {
        if (!first) printf("   ");
        printf("[m]");
    }
}

void print_summary_tail(const Config *cfg, const Totals *tot, bool diff_available,
                         const DebugStats *dbg) {
    if (cfg->modules[MOD_TOTAL]) {
        /* Same [X: value] bracket convention as every per-entry
         * column, not the old plain "label: value" lines -- see
         * docs/plan-ls-rework.md, Category 10. */
        printf("\n%sTOTAL:%s\n", COL(cfg, ANSI_TOTAL), RST(cfg));
        printf("  [dirs: %ld]   [files: %ld]   [lines: %ld]   [chars: %ld]\n",
               tot->dirs, tot->files, tot->lines, tot->chars);
    }

    if (cfg->modules[MOD_DEBUG] && dbg) {
        debug_print_text(dbg, cfg);
    }

    if (cfg->modules[MOD_DIFF] && !diff_available) {
        printf("\n%snote: no previous .ltree snapshot found, run again after --save-output"
               " to enable DIFF%s\n", COL(cfg, ANSI_NOTE), RST(cfg));
    }
}
