/* &desc: "Declares the PrintLine/LineBuf row types and the shared column-rendering pipeline (columns_measure for whole-tree/whole-listing width, columns_measure_fixed for --live's fixed widths, columns_print_line, --condense- and -o O-aware) that render_tree.c and render_ls.c both build on, plus print_summary_tail for the shared TOTAL:/DEBUG:/DIFF-note tail." */
/* columns.h -- the flattened printable row (PrintLine) and the -o
 * column-rendering pipeline (measure every active column's text/width,
 * then print it aligned), shared by the recursive tree view
 * (render_tree.c) and the flat ls-style view (render_ls.c). Pulled out
 * of render_tree.c once render_ls.c needed the exact same "measure,
 * then print aligned brackets" logic -- see docs/plan-ls-rework.md,
 * Category 2. */
#ifndef LTREE_RENDER_COLUMNS_H
#define LTREE_RENDER_COLUMNS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>
#include "core/node.h"
#include "core/config.h"
#include "core/modules.h"
#include "hash/hash.h"
#include "scan/scan.h"
#include "debug/debug.h"

typedef struct {
    char    *prefix;      /* plain, no colour: tree connector glyphs, or
                            * "" in ls mode, which has no tree to draw   */
    char    *name;        /* possibly extension-stripped display name    */
    bool     is_dir;
    bool     is_symlink;
    bool     truncated;
    long     lines, chars;
    mode_t   mode;
    int64_t  size_bytes;
    time_t   mtime;
    uint8_t  hash[HASH_MAX_BYTES];
    uint8_t  hash_len;
    char    *desc;        /* -o DESC text, or NULL (see core/node.h)     */
    bool     diff_checked;
    bool     modified;
    size_t   width;       /* utf8 display width of prefix+name(+"/")     */
} PrintLine;

typedef struct {
    PrintLine *items;
    size_t     n, cap;
} LineBuf;

void       linebuf_init(LineBuf *lb);
PrintLine *linebuf_push(LineBuf *lb);
void       linebuf_free(LineBuf *lb);

/* Fills every field of `pl` from `n` except `prefix`/`width`, which the
 * caller sets afterwards (tree mode builds a connector string; ls mode
 * leaves prefix as ""). Applies EXT display-name stripping per cfg. */
void printline_fill(PrintLine *pl, Node *n, const Config *cfg);

#define RENDER_COLUMN_COUNT 7
extern const ModuleId RENDER_COLUMNS[RENDER_COLUMN_COUNT];

typedef struct {
    ModuleId order[RENDER_COLUMN_COUNT];   /* slot mi's module id -- fixed
                                             * L/C/P/S/D/H order, unless
                                             * -o ...,O asked to respect
                                             * -o argument order instead */
    bool    active[RENDER_COLUMN_COUNT];
    size_t  colwidth[RENDER_COLUMN_COUNT];
    char  **rendered[RENDER_COLUMN_COUNT]; /* rendered[mi][i], line i's text */
    bool    any_module;
} MeasuredColumns;

/* Pass 1: for every active LINES/CHARS/PERMISSIONS/SIZE/DATE/HASH/DESC
 * column, render every line's text (plain, no colour) and track that
 * column's own max width across the whole of `lb`. Caller must call
 * columns_free() when done with `mc`. */
void columns_measure(const LineBuf *lb, const Config *cfg, MeasuredColumns *mc);

/* Same as columns_measure(), but every column's width is a fixed
 * constant (see columns.c) instead of the actual widest value in
 * `lb` -- used by --live, where the widest value anywhere isn't known
 * yet (nothing beyond the current directory has been scanned), so
 * columns still need to line up at a predictable position rather than
 * a computed one. If an individual value is wider than its column's
 * fixed constant (an 8-figure line count, say), that one row's
 * following columns just won't line up -- the same kind of overflow
 * any fixed-width table accepts. */
void columns_measure_fixed(const LineBuf *lb, const Config *cfg, MeasuredColumns *mc);

void columns_free(const LineBuf *lb, MeasuredColumns *mc);

/* Pass 2, one line at a time: prints the gap-to-columns padding (using
 * `col_start` as the fixed column-start position) followed by every
 * active column's coloured, width-padded bracket for line index `i`,
 * then the trailing [m] DIFF flag if this line was marked modified.
 * The caller has already printed the name portion of the line. */
void columns_print_line(const MeasuredColumns *mc, const Config *cfg,
                         const PrintLine *pl, size_t i, size_t col_start);

/* The TOTAL:/DEBUG:/DIFF-note tail both the (streaming) -o TREE view
 * and the ls-mode view end with, factored out here so main.c can
 * print just this tail once the walk finishes, after every
 * directory's own block has already streamed to the terminal. */
void print_summary_tail(const Config *cfg, const Totals *tot, bool diff_available,
                         const DebugStats *dbg);

#endif
