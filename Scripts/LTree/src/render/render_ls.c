#define _GNU_SOURCE
#include "render/render_ls.h"
#include "render/colors.h"
#include "render/columns.h"
#include "util/util.h"
#include "core/modules.h"
#include "scan/exttable.h"
#include "sort/sortmodes.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* Pushes one PrintLine for `n` into `lb`, with `indent` (plain, no
 * colour, e.g. "  " or "    ") stored as its prefix -- col_start then
 * only needs `maxw + 8` regardless of how much any given line is
 * indented, the same convention render_tree.c's connector prefixes
 * already use for the exact same reason. */
static void push_line(Node *n, const Config *cfg, const char *indent, LineBuf *lb) {
    PrintLine *pl = linebuf_push(lb);
    printline_fill(pl, n, cfg);
    pl->prefix = strdup(indent);
    pl->width = utf8_width(pl->prefix) + utf8_width(pl->name) + (n->is_dir ? 1 : 0);
}

static void collect(Node *root, Node ***out_dirs, size_t *out_ndirs,
                     Node ***out_files, size_t *out_nfiles) {
    size_t nd = 0, nf = 0;
    for (size_t i = 0; i < root->nchildren; i++) {
        if (root->children[i]->is_dir) nd++; else nf++;
    }
    Node **dirs = (Node **)malloc(sizeof(Node *) * (nd ? nd : 1));
    Node **files = (Node **)malloc(sizeof(Node *) * (nf ? nf : 1));
    size_t di = 0, fi = 0;
    for (size_t i = 0; i < root->nchildren; i++) {
        Node *n = root->children[i];
        if (n->is_dir) dirs[di++] = n; else files[fi++] = n;
    }
    *out_dirs = dirs; *out_ndirs = nd;
    *out_files = files; *out_nfiles = nf;
}

/* Default (no --sort): visible entries first, hidden ones (dotfiles,
 * only present at all when -o HIDDEN let scan.c walk them in the
 * first place) appended after, each group keeping scan.c's existing
 * alphabetical order -- see docs/plan-ls-rework.md, Category 3.
 * Stable re-partition of `arr` in place. */
static void hidden_last(Node **arr, size_t n) {
    if (n == 0) return;
    Node **tmp = (Node **)malloc(sizeof(Node *) * n);
    size_t ti = 0;
    for (size_t i = 0; i < n; i++) if (arr[i]->name[0] != '.') tmp[ti++] = arr[i];
    for (size_t i = 0; i < n; i++) if (arr[i]->name[0] == '.') tmp[ti++] = arr[i];
    memcpy(arr, tmp, sizeof(Node *) * n);
    free(tmp);
}

/* Builds `lb` (dirs first, then files) plus, only for --sort types,
 * the list of [ext] bucket headers to print inline within the files
 * portion: `bucket_at[k]` is the absolute lb index the k'th header
 * belongs immediately before. Caller frees bucket_names/bucket_at. */
static void build_lines(Node *root, const Config *cfg, LineBuf *lb, size_t *ndirs,
                         char ***bucket_names, size_t **bucket_at, size_t *n_buckets) {
    Node **dirs, **files;
    size_t nd, nf;
    collect(root, &dirs, &nd, &files, &nf);

    *bucket_names = NULL;
    *bucket_at = NULL;
    *n_buckets = 0;

    if (cfg->sort.set && cfg->sort.combined) {
        /* combined: one flat list, no Folders/Files split at all. */
        Node **all = (Node **)malloc(sizeof(Node *) * (nd + nf ? nd + nf : 1));
        memcpy(all, dirs, sizeof(Node *) * nd);
        memcpy(all + nd, files, sizeof(Node *) * nf);
        sort_nodes(all, nd + nf, &cfg->sort);
        *ndirs = 0;
        for (size_t i = 0; i < nd + nf; i++) push_line(all[i], cfg, "  ", lb);
        free(all);
        free(dirs); free(files);
        return;
    }

    if (cfg->sort.set) {
        /* --sort takes over ordering entirely for a group -- no
         * separate hidden-last placement layered on top of it. */
        sort_nodes(dirs, nd, &cfg->sort);
        sort_nodes(files, nf, &cfg->sort);
    } else {
        hidden_last(dirs, nd);
        hidden_last(files, nf);
    }

    *ndirs = nd;
    for (size_t i = 0; i < nd; i++) push_line(dirs[i], cfg, "  ", lb);

    bool types = cfg->sort.set && cfg->sort.base == SORT_TYPES;
    if (types && nf > 0) {
        size_t cap = 8, n = 0;
        char **names = (char **)malloc(sizeof(char *) * cap);
        size_t *at = (size_t *)malloc(sizeof(size_t) * cap);
        const char *prev = NULL;
        for (size_t i = 0; i < nf; i++) {
            const char *ext = file_ext(files[i]->name);
            if (!prev || strcasecmp(ext, prev) != 0) {
                if (n == cap) {
                    cap *= 2;
                    names = (char **)realloc(names, sizeof(char *) * cap);
                    at = (size_t *)realloc(at, sizeof(size_t) * cap);
                }
                names[n] = strdup(ext);
                at[n] = *ndirs + i;
                n++;
            }
            prev = ext;
        }
        *bucket_names = names;
        *bucket_at = at;
        *n_buckets = n;
    }
    for (size_t i = 0; i < nf; i++) push_line(files[i], cfg, types ? "    " : "  ", lb);

    free(dirs); free(files);
}

static void print_ls_line(const LineBuf *lb, const MeasuredColumns *mc, const Config *cfg,
                           size_t i, size_t col_start) {
    PrintLine *pl = &lb->items[i];
    bool is_mod = cfg->modules[MOD_DIFF] && pl->diff_checked && pl->modified;
    const char *namecol = is_mod                ? COL(cfg, ANSI_MODIFIED)
                           : pl->is_symlink       ? COL(cfg, ANSI_SYMLINK)
                           : pl->is_dir           ? COL(cfg, ANSI_DIR)
                                                   : COL(cfg, ANSI_FILE);
    printf("%s%s%s%s%s", pl->prefix, namecol, pl->name, pl->is_dir ? "/" : "", RST(cfg));

    columns_print_line(mc, cfg, pl, i, col_start);

    if (pl->truncated) printf("  %s(...)%s", COL(cfg, ANSI_BRANCH), RST(cfg));
    putchar('\n');
}

void print_ls_view(Node *root, const char *display_path, const Config *cfg,
                    const Totals *tot, bool diff_available, const DebugStats *dbg) {
    LineBuf lb;
    linebuf_init(&lb);
    size_t ndirs;
    char **bucket_names; size_t *bucket_at; size_t n_buckets;
    build_lines(root, cfg, &lb, &ndirs, &bucket_names, &bucket_at, &n_buckets);

    size_t maxw = 0;
    for (size_t i = 0; i < lb.n; i++) if (lb.items[i].width > maxw) maxw = lb.items[i].width;
    size_t col_start = maxw + 8;

    MeasuredColumns mc;
    columns_measure(&lb, cfg, &mc);

    printf("%s%s%s\n", COL(cfg, ANSI_DIR), display_path, RST(cfg));

    bool combined = cfg->sort.set && cfg->sort.combined;
    size_t bi = 0;

    if (combined) {
        for (size_t i = 0; i < lb.n; i++) print_ls_line(&lb, &mc, cfg, i, col_start);
    } else {
        if (ndirs > 0) {
            printf("%s[Folders]%s\n", COL(cfg, ANSI_DIR), RST(cfg));
            for (size_t i = 0; i < ndirs; i++) print_ls_line(&lb, &mc, cfg, i, col_start);
        }
        if (lb.n > ndirs) {
            printf("%s[Files]%s\n", COL(cfg, ANSI_FILE), RST(cfg));
            for (size_t i = ndirs; i < lb.n; i++) {
                while (bi < n_buckets && bucket_at[bi] == i) {
                    printf("  %s[%s]%s\n", COL(cfg, ANSI_EXT), bucket_names[bi], RST(cfg));
                    bi++;
                }
                print_ls_line(&lb, &mc, cfg, i, col_start);
            }
        }
    }

    for (size_t k = 0; k < n_buckets; k++) free(bucket_names[k]);
    free(bucket_names);
    free(bucket_at);

    columns_free(&lb, &mc);
    linebuf_free(&lb);

    print_summary_tail(cfg, tot, diff_available, dbg);
}
