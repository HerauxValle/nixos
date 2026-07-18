/* &desc: "Implements the shared PrintLine/LineBuf plumbing and the column-measure-then-print pipeline (columns_measure for actual widest value, columns_measure_fixed for --live's fixed widths, columns_print_line with underflow-clamped padding, condense- and -o O-order-aware) every terminal renderer builds on, plus print_summary_tail." */
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
    for (size_t i = 0; i < lb->n; i++) {
        free(lb->items[i].prefix);
        free(lb->items[i].name);
        free(lb->items[i].desc);
    }
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
    pl->desc = n->desc ? strdup(n->desc) : NULL;
    pl->diff_checked = n->diff_checked;
    pl->modified = n->modified;
}

const ModuleId RENDER_COLUMNS[RENDER_COLUMN_COUNT] = {
    MOD_LINES, MOD_CHARS, MOD_PERM, MOD_SIZE, MOD_DATE, MOD_HASH, MOD_DESC
};

static const char *module_color(const Config *cfg, ModuleId m) {
    switch (m) {
        case MOD_LINES: return COL(cfg, ANSI_LINES);
        case MOD_CHARS: return COL(cfg, ANSI_CHARS);
        case MOD_PERM:  return COL(cfg, ANSI_PERM);
        case MOD_SIZE:  return COL(cfg, ANSI_SIZE);
        case MOD_DATE:  return COL(cfg, ANSI_DATE);
        case MOD_HASH:  return COL(cfg, ANSI_HASH);
        case MOD_DESC:  return COL(cfg, ANSI_DESC);
        default:        return "";
    }
}

static char *render_module_text(ModuleId m, const PrintLine *pl) {
    char buf[512]; /* big enough for DESC's %.480s below; every other
                     * case here is far shorter than 128, unchanged */
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
        case MOD_DESC:
            if (pl->desc) snprintf(buf, sizeof(buf), "[DESC: %.480s]", pl->desc);
            else          snprintf(buf, sizeof(buf), "[DESC: -]");
            break;
        default:
            buf[0] = '\0';
    }
    return strdup(buf);
}

/* Fills mc->order[]: the fixed L/C/P/S/D/H order, unless -oO asked
 * to respect -o argument order instead (see docs/plan-ls-rework.md,
 * Category 5, and docs/plan-hash-desc-spinner.md's addendum on -oA/
 * -oO's final syntax). cfg->order_seen may also contain TOTAL/
 * DEBUG/etc from the same -o list (anything MODCAT_COLUMN or not) --
 * this filters down to just the six column modules, in the order they
 * were typed, then appends whichever column modules weren't typed at
 * all (in fixed order) so all six always end up placed exactly once. */
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

/* Generous-but-plausible fixed widths for --live (see columns.h) --
 * PERMISSIONS and DATE are already naturally this width on every run
 * (mode_string()/format_datetime_local() never produce anything
 * else), so "fixing" them just documents that; LINES/CHARS/SIZE/HASH
 * are the ones that actually vary and need a real constant. */
static size_t fixed_colwidth_for(ModuleId m) {
    switch (m) {
        case MOD_LINES: return 13; /* "[L: 99999999]"        -- 8-digit lines  */
        case MOD_CHARS: return 15; /* "[C: 9999999999]"      -- 10-digit chars */
        case MOD_PERM:  return 15; /* "[P: -rwxr-xr-x]"      -- always this    */
        case MOD_SIZE:  return 11; /* "[S: 999.9G]"          -- human_size max */
        case MOD_DATE:  return 24; /* "[D: dd-mm-yyyy hh:mm:ss]" -- always this */
        case MOD_HASH:  return 21; /* "[H: xxxxxxxxxxxxxxxx]" -- 16 hex chars  */
        case MOD_DESC:  return 30; /* generous guess -- real descriptions vary
                                     * wildly in length, same overflow-allowed
                                     * tradeoff as everywhere else in --live  */
        default:        return 0;
    }
}

void columns_measure_fixed(const LineBuf *lb, const Config *cfg, MeasuredColumns *mc) {
    mc->any_module = false;
    resolve_column_order(cfg, mc->order);
    for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
        ModuleId m = mc->order[mi];
        mc->active[mi] = cfg->modules[m];
        mc->colwidth[mi] = fixed_colwidth_for(m);
        mc->rendered[mi] = NULL;
        if (!mc->active[mi]) continue;
        mc->any_module = true;
        mc->rendered[mi] = (char **)malloc(sizeof(char *) * (lb->n ? lb->n : 1));
        for (size_t i = 0; i < lb->n; i++) {
            mc->rendered[mi][i] = render_module_text(m, &lb->items[i]);
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

    /* --condense wrap: every active column gets its own line, indented
     * to col_start from column 0 -- nothing shares the entry's name
     * line at all (unlike CONDENSE_BRACKET/off, which print the first
     * column right after the name). The caller's own trailing newline
     * (after this function returns) closes out the last column's line,
     * same as it closes out the single line in every other mode. */
    if (cfg->condense == CONDENSE_WRAP && mc->any_module) {
        for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
            if (!mc->active[mi]) continue;
            putchar('\n');
            for (size_t s = 0; s < col_start; s++) putchar(' ');
            printf("%s%s%s", module_color(cfg, mc->order[mi]), mc->rendered[mi][i], RST(cfg));
        }
        if (is_mod) printf("   [m]");
        return;
    }

    size_t pad = (col_start > pl->width) ? (col_start - pl->width) : 1;
    for (size_t s = 0; s < pad; s++) putchar(' ');

    /* --condense: one [L:x C:y ...] bracket instead of one bracket per
     * column, still colour-coded per field, no per-column width
     * padding inside it (that's the whole point -- tight, not
     * columnar). The [m] DIFF flag stays a separate trailing marker,
     * same as uncondensed -- it's a modification flag, not one of the
     * data columns condense is folding together. */
    if (cfg->condense == CONDENSE_BRACKET && mc->any_module) {
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
        /* Clamped, not a bare subtraction: with columns_measure_fixed()
         * (--live), colwidth is a constant that a genuinely long value
         * (an 8-figure line count, say) can exceed -- an unguarded
         * `colwidth - strlen(text)` would underflow (both size_t) into
         * a huge padding count instead of just leaving that one row
         * unaligned. Never triggers under plain columns_measure(),
         * where colwidth is always >= every individual width by
         * construction. */
        size_t tlen = strlen(text);
        size_t pad2 = (mc->colwidth[mi] > tlen) ? (mc->colwidth[mi] - tlen) : 0;
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
