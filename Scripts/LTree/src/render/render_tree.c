#define _GNU_SOURCE
#include "render/render_tree.h"
#include "render/colors.h"
#include "render/columns.h"
#include "util/util.h"
#include "core/modules.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===================== recursive flatten (tree mode only) ================
 * ls mode (render_ls.c) doesn't recurse and has no connector prefixes
 * to draw, so it builds its own LineBuf directly rather than sharing
 * this function -- but both share the PrintLine/LineBuf shape and the
 * whole column-rendering pipeline below, see render/columns.h. */
static void flatten(Node *n, const Config *cfg, const char *prefix,
                     bool is_last, bool is_root, LineBuf *lb) {
    if (!is_root) {
        PrintLine *pl = linebuf_push(lb);
        const char *connector = is_last ? "\xE2\x95\xB0\xE2\x94\x80\xE2\x94\x80 " /* ╰── */
                                         : "\xE2\x94\x9C\xE2\x94\x80\xE2\x94\x80 " /* ├── */;
        size_t plen = strlen(prefix) + strlen(connector) + 1;
        pl->prefix = (char *)malloc(plen);
        snprintf(pl->prefix, plen, "%s%s", prefix, connector);

        printline_fill(pl, n, cfg);
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

/* ===================== tree (human) output =============================== */
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
                               : pl->is_dir           ? COL(cfg, ANSI_DIR)
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
