#define _GNU_SOURCE
#include "render/render_live.h"
#include "render/colors.h"
#include "render/columns.h"
#include "util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void render_live_dir_block(Node *dir, const char *relpath, const Config *cfg, void *ctx) {
    (void)ctx;

    LineBuf lb;
    linebuf_init(&lb);
    for (size_t i = 0; i < dir->nchildren; i++) {
        Node *n = dir->children[i];
        PrintLine *pl = linebuf_push(&lb);
        printline_fill(pl, n, cfg);
        pl->prefix = strdup("  ");
        pl->width = utf8_width(pl->prefix) + utf8_width(pl->name) + (n->is_dir ? 1 : 0);
    }

    size_t maxw = 0;
    for (size_t i = 0; i < lb.n; i++) if (lb.items[i].width > maxw) maxw = lb.items[i].width;
    size_t col_start = maxw + 8;

    MeasuredColumns mc;
    columns_measure(&lb, cfg, &mc);

    const char *label = (relpath[0] == '\0') ? "." : relpath;
    printf("%s%s/%s\n", COL(cfg, ANSI_DIR), label, RST(cfg));

    for (size_t i = 0; i < lb.n; i++) {
        PrintLine *pl = &lb.items[i];
        const char *namecol = pl->is_symlink ? COL(cfg, ANSI_SYMLINK)
                             : pl->is_dir     ? COL(cfg, ANSI_DIR)
                                              : COL(cfg, ANSI_FILE);
        printf("%s%s%s%s%s", pl->prefix, namecol, pl->name, pl->is_dir ? "/" : "", RST(cfg));
        columns_print_line(&mc, cfg, pl, i, col_start);
        if (pl->truncated) printf("  %s(...)%s", COL(cfg, ANSI_BRANCH), RST(cfg));
        putchar('\n');
    }

    columns_free(&lb, &mc);
    linebuf_free(&lb);
    fflush(stdout);
}
