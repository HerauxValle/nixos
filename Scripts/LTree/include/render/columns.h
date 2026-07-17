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

#define RENDER_COLUMN_COUNT 6
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

/* Pass 1: for every active LINES/CHARS/PERMISSIONS/SIZE/DATE/HASH
 * column, render every line's text (plain, no colour) and track that
 * column's own max width across the whole of `lb`. Caller must call
 * columns_free() when done with `mc`. */
void columns_measure(const LineBuf *lb, const Config *cfg, MeasuredColumns *mc);
void columns_free(const LineBuf *lb, MeasuredColumns *mc);

/* Pass 2, one line at a time: prints the gap-to-columns padding (using
 * `col_start` as the fixed column-start position) followed by every
 * active column's coloured, width-padded bracket for line index `i`,
 * then the trailing [m] DIFF flag if this line was marked modified.
 * The caller has already printed the name portion of the line. */
void columns_print_line(const MeasuredColumns *mc, const Config *cfg,
                         const PrintLine *pl, size_t i, size_t col_start);

/* The TOTAL:/DEBUG:/DIFF-note tail both print_tree_view() and
 * print_ls_view() end with, factored out here so --live (which skips
 * both of those views and streams per-directory blocks during the
 * scan instead, see render/render_live.h) can print just this tail
 * once the walk finishes. */
void print_summary_tail(const Config *cfg, const Totals *tot, bool diff_available,
                         const DebugStats *dbg);

#endif
