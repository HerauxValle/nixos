/* &desc: "Implements the shared PrintLine/LineBuf plumbing and the column-measure-then-print pipeline (columns_measure for actual widest value, columns_measure_fixed for --live's fixed widths, columns_print_line with underflow-clamped padding, condense- and -o O-order-aware) every terminal renderer builds on, plus print_summary_tail." */
#define _GNU_SOURCE
#include "render/columns.h"
#include "render/colors.h"
#include "util/util.h"
#include "scan/exttable.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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
        free(lb->items[i].guide);
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

/* ===================== terminal-width-aware line wrapping =============
 * Shared by every --condense mode (off/BRACKET/WRAP alike): a long -o
 * DESC value (up to 480 raw bytes, see MOD_DESC in
 * render_module_text()) is routinely well past any real terminal
 * width. Without this, the TERMINAL itself hard-wraps that one long
 * printed line wherever the window happens to end -- with zero
 * indentation on the leftover fragment, which is what actually breaks
 * a tree's vertical guide bars (the fragment lands with no bars at
 * all, right before the next entry). This tracks the cursor's real
 * column position and wraps *itself*, reprinting the entry's ancestor
 * guide bars + padding on every continuation line, so the fragment
 * never loses its indentation regardless of which condense mode (or
 * none) produced it. ===================================================== */
typedef struct {
    const Config *cfg;
    const char   *guide;      /* pl->guide -- ancestor bars, no connector */
    size_t        guide_pad;  /* spaces after guide to reach col_start */
    size_t        col_start;
    size_t        term_w;     /* 0 == not a tty / too narrow: never wrap */
    size_t        col;        /* current absolute display column */
    bool          wrapped;    /* has lc_newline() fired at least once yet --
                                * columns_print_line() reads this to switch
                                * from "pack columns onto the name's line"
                                * to "one column per line" the moment ANY
                                * column needed the room, see its own
                                * comment there. */
} LineCursor;

static void lc_init(LineCursor *lc, const Config *cfg, const char *guide, size_t col_start) {
    lc->cfg = cfg;
    lc->guide = guide;
    size_t term_w = isatty(STDOUT_FILENO) ? terminal_width() : 0;

    /* col_start is a GLOBAL alignment column -- the widest name+prefix
     * ANYWHERE in the tree, shared by every row so every [DESC:...]
     * lines up. One deeply nested entry elsewhere can push it past the
     * terminal's actual width; when that happens, wrapping used to be
     * disabled for the ENTIRE run (every row shares the same
     * col_start), which meant an otherwise-short, otherwise-fine row
     * like a shallow "flake" got its long DESC dumped as one giant
     * unwrapped line for the terminal to mangle -- exactly the bug
     * this file exists to prevent, just reintroduced by an over-broad
     * guard. Falling back to just past THIS row's own guide keeps
     * wrapping working (guide bars, natural break points, all of it)
     * even though continuation lines won't align with col_start-based
     * rows anymore -- there's no usable alignment to offer once the
     * shared column itself doesn't fit, but there's still plenty of
     * room to wrap sanely within. Only a terminal narrower than the
     * guide bars themselves is truly hopeless and disables wrapping. */
    size_t guide_w = utf8_width(guide);
    size_t eff_col_start = (term_w > 0 && col_start + 10 > term_w) ? guide_w + 2 : col_start;

    lc->col_start = eff_col_start;
    lc->guide_pad = (eff_col_start > guide_w) ? (eff_col_start - guide_w) : 0;
    lc->term_w = (term_w > eff_col_start) ? term_w : 0;
    lc->col = 0; /* set for real by lc_pad_from(), which must run after this */
    lc->wrapped = false;
}

/* Pads from the cursor's current column (`from` -- pl->width, right
 * after the caller printed the entry's own name) out to lc->col_start,
 * and sets lc->col to wherever that actually lands. Must run AFTER
 * lc_init(), never before it: lc_init() may have already shrunk
 * col_start to a smaller effective value because the GLOBAL one
 * (shared by every row in the tree) doesn't fit this terminal -- padding
 * with the raw, still-too-wide col_start before lc_init() gets a say
 * walks the cursor out past the terminal edge before any wrap-aware
 * code runs at all, so even a trivially short "[DESC: -]" looks like it
 * doesn't fit and gets shoved onto a line of its own. That was the
 * actual bug behind entries getting pointless extra lines even without
 * --condense: the old single `pad` loop in columns_print_line() ran
 * before lc_init() existed to shrink anything. */
static void lc_pad_from(LineCursor *lc, size_t from) {
    size_t pad = (lc->col_start > from) ? (lc->col_start - from) : 1;
    for (size_t s = 0; s < pad; s++) putchar(' ');
    lc->col = from + pad;
}

static void lc_newline(LineCursor *lc) {
    putchar('\n');
    printf("%s%s%s", COL(lc->cfg, ANSI_BRANCH), lc->guide, RST(lc->cfg));
    for (size_t s = 0; s < lc->guide_pad; s++) putchar(' ');
    lc->col = lc->col_start;
    lc->wrapped = true;
}

static bool is_ascii_letter(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

/* How far back from the hard width limit to look for a natural break
 * point before giving up and slicing mid-word. Small enough that a
 * short field never gets an absurdly early break, generous enough to
 * usually find the end of the word DESC's 480-char text happened to
 * land on. */
#define WRAP_LOOKBACK 24

/* Chooses where to end the current chunk of a too-long-for-one-line
 * field, given the hard UTF-8-width limit `avail` counted from
 * `start`. Prefers, scanning backward from the limit: a space (the
 * chunk ends before it, the space itself is dropped -- the next chunk
 * starts clean); a comma or period (kept on THIS chunk, since it's
 * trailing punctuation, not a word start); a '-' directly between two
 * ASCII letters, i.e. a hyphenated compound like "no-cli" (also kept
 * on this chunk, splitting after the hyphen the way a dictionary
 * would). Falls back to the hard limit (mid-word) only when nothing
 * break-worthy shows up within WRAP_LOOKBACK of it. Returns a pointer
 * into `start`'s buffer at the chosen cut (exclusive end of this
 * chunk) and sets *skip_bytes to however many trailing bytes (a
 * dropped space) the NEXT chunk should skip past. */
static const unsigned char *find_break(const unsigned char *start, size_t avail,
                                        size_t *skip_bytes) {
    *skip_bytes = 0;
    const unsigned char *hard_end = start;
    size_t w = 0;
    while (*hard_end && w < avail) {
        hard_end++;
        while ((*hard_end & 0xC0) == 0x80) hard_end++;
        w++;
    }
    if (!*hard_end) return hard_end; /* text ends exactly at/before the limit */

    size_t lookback = w < WRAP_LOOKBACK ? w : WRAP_LOOKBACK;
    const unsigned char *scan = hard_end;
    for (size_t k = 0; k < lookback; k++) {
        scan--;
        while (scan > start && (*scan & 0xC0) == 0x80) scan--;
        unsigned char c = *scan;
        if (c == ' ') { *skip_bytes = 1; return scan; }
        if (c == ',' || c == '.') return scan + 1;
        if (c == '-' && scan > start && scan + 1 < hard_end &&
            is_ascii_letter(*(scan - 1)) && is_ascii_letter(*(scan + 1))) {
            return scan + 1;
        }
    }
    return hard_end; /* nothing break-worthy nearby -- hard cut */
}

/* Prints purely cosmetic text -- inter-column separators ("   "),
 * bracket punctuation ("[", "]", " "), and column-alignment padding --
 * that must NEVER trigger a wrap on its own. Padding in particular can
 * be huge: colwidth[mi] is the widest rendered value for that column
 * ACROSS THE WHOLE TREE, so a short "[DESC: -]" next to some other
 * entry's 400-character DESC elsewhere gets padded with hundreds of
 * spaces -- running that through lc_print() (which treats "does this
 * fit" as a real wrap decision) turned pure alignment whitespace into
 * a cascade of spurious blank continuation lines, one of the exact
 * bugs this file exists to prevent, just self-inflicted this time. */
static void lc_raw(LineCursor *lc, const char *text) {
    printf("%s", text);
    lc->col += utf8_width(text);
}

/* Prints `text` in `color` at the cursor's current column, wrapping to
 * a fresh guide-indented line whenever continuing here would overflow
 * the terminal. A value that doesn't fit where we are but WOULD fit on
 * a whole fresh line (typical case: a short column after a long one)
 * moves there wholesale, never split internally -- only a value too
 * wide even for that (DESC territory, realistically the only column
 * that ever gets this long) is hard-chunked across as many
 * continuation lines as it needs, preferring natural break points via
 * find_break() over slicing mid-word. */
static void lc_print(LineCursor *lc, const char *text, const char *color) {
    size_t tw = utf8_width(text);
    if (lc->term_w == 0 || lc->col + tw <= lc->term_w) {
        printf("%s%s%s", color, text, RST(lc->cfg));
        lc->col += tw;
        return;
    }

    if (lc->col > lc->col_start) lc_newline(lc);
    if (lc->col_start + tw <= lc->term_w) {
        printf("%s%s%s", color, text, RST(lc->cfg));
        lc->col += tw;
        return;
    }

    const unsigned char *p = (const unsigned char *)text;
    bool first_chunk = true;
    while (*p) {
        if (!first_chunk) lc_newline(lc);
        first_chunk = false;
        /* A small margin off the hard edge so a wrap doesn't look like
         * it's crammed right up against the terminal's last column --
         * find_break() still searches back from here for a real break
         * char rather than cutting exactly on the margin. */
        size_t avail = lc->term_w - lc->col;
        avail = avail > 2 ? avail - 2 : avail;

        size_t skip_bytes;
        const unsigned char *start = p;
        const unsigned char *cut = find_break(start, avail, &skip_bytes);
        printf("%s%.*s%s", color, (int)(cut - start), start, RST(lc->cfg));
        size_t chunk_w = 0;
        for (const unsigned char *q = start; q < cut; q++)
            if ((*q & 0xC0) != 0x80) chunk_w++;
        lc->col += chunk_w;
        p = cut + skip_bytes;
    }
}

void columns_print_line(const MeasuredColumns *mc, const Config *cfg,
                         const PrintLine *pl, size_t i, size_t col_start) {
    bool is_mod = cfg->modules[MOD_DIFF] && pl->diff_checked && pl->modified;

    if (!mc->any_module && !is_mod) return;

    const char *guide = pl->guide ? pl->guide : "";

    LineCursor lc;
    lc_init(&lc, cfg, guide, col_start);
    lc_pad_from(&lc, pl->width);

    /* --condense: one [L:x C:y ...] bracket instead of one bracket per
     * column, still colour-coded per field, no per-column width
     * padding inside it (that's the whole point -- tight, not
     * columnar). The [m] DIFF flag stays a separate trailing marker,
     * same as uncondensed -- it's a modification flag, not one of the
     * data columns condense is folding together. */
    if (cfg->condense && mc->any_module) {
        lc_raw(&lc, "[");
        bool first = true;
        for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
            if (!mc->active[mi]) continue;
            if (!first) lc_raw(&lc, " ");
            first = false;
            char buf[128];
            condense_field(mc->rendered[mi][i], buf, sizeof(buf));
            lc_print(&lc, buf, module_color(cfg, mc->order[mi]));
        }
        lc_raw(&lc, "]");
        if (is_mod) printf("   [m]");
        return;
    }

    /* Without --condense: columns stay separate (unlike --condense's
     * single folded-together "[...]"), and share the entry's own line
     * for as long as everything actually fits -- a short "[DESC: -]"
     * has no reason to be pushed onto a line of its own. Wrapping
     * kicks in once something genuinely doesn't fit: from the column
     * that first needed the room onward, every remaining column is
     * forced onto its own fresh guide-indented line (lc.wrapped, set
     * by lc_newline() and checked below), so once a row starts
     * breaking it reads as a clean one-bracket-per-line stack instead
     * of a ragged mix of packed and wrapped columns. This used to be a
     * separate --condense wrap mode; folded into the unconditional
     * default since every render needs to handle overflow this way
     * regardless of --condense, and keeping two separate
     * pack-and-wrap implementations around was just two places for the
     * same class of bug to hide in. */
    bool first = true;
    for (int mi = 0; mi < RENDER_COLUMN_COUNT; mi++) {
        if (!mc->active[mi]) continue;
        if (lc.wrapped) lc_newline(&lc);
        else if (!first) lc_raw(&lc, "   ");
        first = false;
        lc_print(&lc, mc->rendered[mi][i], module_color(cfg, mc->order[mi]));
    }
    if (is_mod) {
        if (lc.wrapped) lc_newline(&lc);
        else lc_raw(&lc, "   ");
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
