/* &desc: "Implements print_tree_view (buffered, flattens the complete tree then measures/prints whole-tree-aligned) and the tree_live_* streaming hooks (--live, fixed-width columns, per-depth prefix queue-free since recursion is interleaved) for -o TREE." */
#define _GNU_SOURCE
#include "render/render_tree.h"
#include "render/colors.h"
#include "render/columns.h"
#include "render/namecolor.h"
#include "util/util.h"
#include "util/spinner.h"
#include "core/modules.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===================== buffered, whole-tree-aligned (default) ===========
 * The classic behavior: build_tree() has already returned with the
 * complete Node tree, so flatten() walks all of it once into one
 * LineBuf, columns_measure() sizes every active column against every
 * entry in the whole tree, then everything prints. Nothing streams --
 * see tree_live_* below for --live's alternative. ===================== */
static void flatten(Node *n, const Config *cfg, const char *prefix,
                     bool is_last, bool is_root, LineBuf *lb) {
    /* childprefix = this entry's own branch stem, one level past its
     * ancestors': "│   " if it has more siblings still to come (so
     * that stem keeps running down to connect to the next one),
     * "    " if it's the last sibling (nothing left to connect to).
     * Computed for every non-root entry regardless of is_dir -- a
     * directory recurses into it for real children below, but every
     * entry (file or dir) also uses it as pl->guide, since a wrapped
     * column block is visually "underneath" the entry the exact same
     * way real children would be, and needs the same
     * stem to keep the tree's vertical line unbroken between this
     * entry and its next sibling (see the "default"/"exclusions" case
     * this fixed -- guide used to stop at the ANCESTOR bars and skip
     * this entry's own connecting stem entirely). */
    char childprefix[4096];
    if (is_root) {
        childprefix[0] = '\0';
    } else {
        const char *cont = is_last ? "    " : "\xE2\x94\x82   " /* │   */;
        snprintf(childprefix, sizeof(childprefix), "%s%s", prefix, cont);
    }

    if (!is_root) {
        PrintLine *pl = linebuf_push(lb);
        const char *connector = is_last ? "\xE2\x95\xB0\xE2\x94\x80\xE2\x94\x80 " /* ╰── */
                                         : "\xE2\x94\x9C\xE2\x94\x80\xE2\x94\x80 " /* ├── */;
        size_t plen = strlen(prefix) + strlen(connector) + 1;
        pl->prefix = (char *)malloc(plen);
        snprintf(pl->prefix, plen, "%s%s", prefix, connector);

        /* pl->guide is childprefix PLUS one more bar segment when this
         * entry has real children -- childprefix alone (is_last-based)
         * is right for reaching the next SIBLING, but a directory with
         * children needs the stem even as the LAST sibling, to connect
         * down into its own first child instead (see docs -- the
         * "users/" -> "default" case: users/ is the last entry at its
         * level, so childprefix is blank there, but its wrap
         * continuation still needs a bar, positioned exactly where
         * default's own connector will land, i.e. one full childprefix
         * further in -- hence appending a whole extra segment rather
         * than just flipping childprefix's own blank to a bar). */
        bool has_children = n->is_dir && n->nchildren > 0;
        size_t glen = strlen(childprefix) + (has_children ? strlen("\xE2\x94\x82   ") : 0) + 1;
        pl->guide = (char *)malloc(glen);
        snprintf(pl->guide, glen, "%s%s", childprefix, has_children ? "\xE2\x94\x82   " /* │   */ : "");

        printline_fill(pl, n, cfg);
        pl->namecolor = n->is_dir ? dir_name_color(cfg, n->name)
                                   : file_name_color(cfg, n->name, n->mode);
        pl->width = utf8_width(pl->prefix) + utf8_width(pl->name) + (n->is_dir ? 1 : 0);
    }

    if (!n->is_dir) return;

    for (size_t i = 0; i < n->nchildren; i++) {
        bool last = (i == n->nchildren - 1);
        flatten(n->children[i], cfg, childprefix, last, false, lb);
    }
}

void print_tree_view(Node *root, const char *display_path, const Config *cfg,
                      const Totals *tot, bool diff_available, const DebugStats *dbg) {
    LineBuf lb;
    linebuf_init(&lb);
    flatten(root, cfg, "", true, true, &lb);

    size_t maxw = utf8_width(display_path);
    for (size_t i = 0; i < lb.n; i++) if (lb.items[i].width > maxw) maxw = lb.items[i].width;
    size_t col_start = maxw + 8;

    MeasuredColumns mc;
    columns_measure(&lb, cfg, &mc);

    printf("%s%s%s\n", COL(cfg, ANSI_DIR), display_path, RST(cfg));

    for (size_t i = 0; i < lb.n; i++) {
        PrintLine *pl = &lb.items[i];
        bool is_mod = cfg->modules[MOD_DIFF] && pl->diff_checked && pl->modified;
        const char *namecol = is_mod                ? COL(cfg, ANSI_MODIFIED)
                               : pl->is_symlink       ? COL(cfg, ANSI_SYMLINK)
                               : pl->is_dir           ? (pl->namecolor ? pl->namecolor : COL(cfg, ANSI_DIR))
                               : pl->namecolor        ? pl->namecolor
                                                       : COL(cfg, ANSI_FILE);
        printf("%s%s%s%s%s%s%s", COL(cfg, ANSI_BRANCH), pl->prefix, RST(cfg),
               namecol, pl->name, pl->is_dir ? "/" : "", RST(cfg));

        columns_print_line(&mc, cfg, pl, i, col_start);

        if (pl->truncated) printf("  %s(...)%s", COL(cfg, ANSI_BRANCH), RST(cfg));
        putchar('\n');
    }

    columns_free(&lb, &mc);
    linebuf_free(&lb);

    print_summary_tail(cfg, tot, diff_available, dbg);
}

/* ===================== --live: streamed, fixed-width columns ============
 * Two things are threaded from a directory down to its children, both
 * indexed by depth (the depth of the ENTRIES being printed, i.e. one
 * more than their parent directory's own depth):
 *
 *   - `prefix`: the connector-ancestor string entries at this depth
 *     print before their own ├──/╰──. Set by the PARENT's
 *     on_entry_ready call (computed from ITS OWN prefix + whether the
 *     parent itself was last among its siblings), read by
 *     on_dir_measure when building this depth's PrintLines.
 *   - `lb`/`mc`/`col_start`: this depth's siblings, measured once (by
 *     on_dir_measure, via columns_measure_fixed() -- FIXED widths,
 *     not the widest value in `lb`, since nothing beyond the current
 *     directory is known yet) so per-entry printing (on_entry_ready)
 *     can print aligned columns without knowing the rest of the tree.
 *
 * A plain array indexed by depth is safe here (no per-sibling
 * collision) because scan.c's build_tree() recurses one child fully
 * to completion (including everything at deeper depths) before
 * starting the next sibling -- by the time a depth's value would get
 * overwritten by a new directory, the previous occupant's entire
 * subtree has already finished reading it. Static because this is a
 * single-threaded, one-scan-per-process tool (same convention as
 * scan.c's signal-guard globals). ===================================== */
#define TREE_LIVE_COL_START 44

typedef struct {
    char           *prefix;
    LineBuf         lb;
    MeasuredColumns mc;
    bool            have_measurement;
} LiveDepthState;

static LiveDepthState *g_depth = NULL;
static size_t g_depth_cap = 0;

static void ensure_depth(size_t depth) {
    if (depth < g_depth_cap) return;
    size_t new_cap = depth + 16;
    g_depth = (LiveDepthState *)realloc(g_depth, sizeof(LiveDepthState) * new_cap);
    for (size_t i = g_depth_cap; i < new_cap; i++) {
        g_depth[i].prefix = NULL;
        g_depth[i].have_measurement = false;
        memset(&g_depth[i].lb, 0, sizeof(LineBuf));
        memset(&g_depth[i].mc, 0, sizeof(MeasuredColumns));
    }
    g_depth_cap = new_cap;
}

void tree_live_start(const char *display_path, const Config *cfg) {
    printf("%s%s%s\n", COL(cfg, ANSI_DIR), display_path, RST(cfg));
    fflush(stdout);
    spinner_tick(true); /* spinner appears right under the path line */
    ensure_depth(2);
    free(g_depth[1].prefix);
    g_depth[1].prefix = strdup("");
}

void tree_live_on_dir_measure(Node *dir, int depth, const Config *cfg, void *ctx) {
    (void)ctx;
    size_t child_depth = (size_t)depth + 1;
    ensure_depth(child_depth + 1);

    const char *prefix = g_depth[child_depth].prefix ? g_depth[child_depth].prefix : "";

    LineBuf *lb = &g_depth[child_depth].lb;
    linebuf_init(lb);
    for (size_t i = 0; i < dir->nchildren; i++) {
        Node *n = dir->children[i];
        bool is_last = (i + 1 == dir->nchildren);
        const char *connector = is_last ? "\xE2\x95\xB0\xE2\x94\x80\xE2\x94\x80 " /* ╰── */
                                         : "\xE2\x94\x9C\xE2\x94\x80\xE2\x94\x80 " /* ├── */;

        PrintLine *pl = linebuf_push(lb);
        printline_fill(pl, n, cfg);
        size_t plen = strlen(prefix) + strlen(connector) + 1;
        pl->prefix = (char *)malloc(plen);
        snprintf(pl->prefix, plen, "%s%s", prefix, connector);
        /* Same fix as flatten() in the buffered path above: guide is
         * childprefix (ancestor bars + this entry's own stem, "│   "
         * unless it's the last sibling) PLUS one more bar segment when
         * this entry has real children -- a directory needs the stem
         * even as the last sibling, to connect down into its own first
         * child instead of a next sibling that doesn't exist. */
        const char *own_cont = is_last ? "    " : "\xE2\x94\x82   " /* │   */;
        size_t cplen = strlen(prefix) + strlen(own_cont) + 1;
        char *childprefix = (char *)malloc(cplen);
        snprintf(childprefix, cplen, "%s%s", prefix, own_cont);

        bool has_children = n->is_dir && n->nchildren > 0;
        size_t glen = strlen(childprefix) + (has_children ? strlen("\xE2\x94\x82   ") : 0) + 1;
        pl->guide = (char *)malloc(glen);
        snprintf(pl->guide, glen, "%s%s", childprefix, has_children ? "\xE2\x94\x82   " /* │   */ : "");
        free(childprefix);
        pl->namecolor = n->is_dir ? dir_name_color(cfg, n->name)
                                   : file_name_color(cfg, n->name, n->mode);
        pl->width = utf8_width(pl->prefix) + utf8_width(pl->name) + (n->is_dir ? 1 : 0);
    }

    columns_measure_fixed(lb, cfg, &g_depth[child_depth].mc);
    g_depth[child_depth].have_measurement = true;
}

void tree_live_on_entry_ready(Node *node, size_t index, bool is_last, int depth,
                               const Config *cfg, void *ctx) {
    (void)ctx;
    size_t d = (size_t)depth;
    ensure_depth(d + 1);
    LiveDepthState *ds = &g_depth[d];
    PrintLine *pl = &ds->lb.items[index];

    /* -o DIFF can't mark anything here -- diffing needs the complete
     * tree, which only exists after the whole walk finishes, well
     * after this line has already printed. */
    const char *namecol = pl->is_symlink ? COL(cfg, ANSI_SYMLINK)
                        : pl->is_dir     ? (pl->namecolor ? pl->namecolor : COL(cfg, ANSI_DIR))
                        : pl->namecolor  ? pl->namecolor
                                         : COL(cfg, ANSI_FILE);

    /* Erase the spinner before this real line prints, then redraw it
     * immediately after -- keeps it "always the bottom line" through the
     * whole streamed walk (see util/spinner.h). */
    spinner_erase();
    printf("%s%s%s%s%s%s%s", COL(cfg, ANSI_BRANCH), pl->prefix, RST(cfg),
           namecol, pl->name, pl->is_dir ? "/" : "", RST(cfg));

    columns_print_line(&ds->mc, cfg, pl, index, TREE_LIVE_COL_START);

    if (pl->truncated) printf("  %s(...)%s", COL(cfg, ANSI_BRANCH), RST(cfg));
    putchar('\n');
    fflush(stdout);
    spinner_tick(true);

    if (node->is_dir && !node->truncated) {
        const char *my_prefix = ds->prefix ? ds->prefix : "";
        const char *cont = is_last ? "    " : "\xE2\x94\x82   " /* │   */;
        size_t clen = strlen(my_prefix) + strlen(cont) + 1;
        char *childprefix = (char *)malloc(clen);
        snprintf(childprefix, clen, "%s%s", my_prefix, cont);

        ensure_depth(d + 2);
        free(g_depth[d + 1].prefix);
        g_depth[d + 1].prefix = childprefix;
    }
}

void tree_live_on_dir_done(int depth, const Config *cfg, void *ctx) {
    (void)cfg;
    (void)ctx;
    size_t d = (size_t)depth;
    if (d < g_depth_cap && g_depth[d].have_measurement) {
        columns_free(&g_depth[d].lb, &g_depth[d].mc);
        linebuf_free(&g_depth[d].lb);
        g_depth[d].have_measurement = false;
    }
}

void tree_live_end(void) {
    for (size_t i = 0; i < g_depth_cap; i++) {
        free(g_depth[i].prefix);
        if (g_depth[i].have_measurement) {
            columns_free(&g_depth[i].lb, &g_depth[i].mc);
            linebuf_free(&g_depth[i].lb);
        }
    }
    free(g_depth);
    g_depth = NULL;
    g_depth_cap = 0;
}
