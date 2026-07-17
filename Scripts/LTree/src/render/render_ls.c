/* &desc: "Implements print_ls_view, the default [Folders]/[Files] listing: packs entries into an ls -C style multi-column grid on a tty when no -o data columns are active, falls back to one-per-line otherwise (piped output, or with columns), full --sort integration including the types extension-bucket sub-headers." */
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
#include <unistd.h>
#include <sys/ioctl.h>

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

static size_t terminal_width(void) {
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) return ws.ws_col;
    const char *cols_env = getenv("COLUMNS");
    if (cols_env) {
        int c = atoi(cols_env);
        if (c > 0) return (size_t)c;
    }
    return 80;
}

/* Name(+slash) width, plus " [m]" if -o DIFF marked this entry --
 * deliberately NOT pl->width, which bakes in the one-per-line "  "/
 * "    " indent prefix that a packed grid manages itself. */
static size_t entry_grid_width(const PrintLine *pl, const Config *cfg) {
    size_t w = utf8_width(pl->name) + (pl->is_dir ? 1 : 0);
    bool is_mod = cfg->modules[MOD_DIFF] && pl->diff_checked && pl->modified;
    if (is_mod) w += 4; /* " [m]" */
    return w;
}

/* Packs [from,to) into a column-major grid the way plain `ls` (no
 * -l/-o data columns) lays out a terminal listing: fill down the
 * first column, then the next, using as many columns as fit
 * `term_width`, each column padded to its own widest entry. */
static void print_grid(const LineBuf *lb, size_t from, size_t to, const Config *cfg,
                        size_t term_width) {
    size_t n = to - from;
    if (n == 0) return;

    const size_t gap = 2;
    const size_t margin = 2; /* leading "  " indent, matches the non-grid rows */

    size_t *w = (size_t *)malloc(sizeof(size_t) * n);
    size_t maxw = 0;
    for (size_t i = 0; i < n; i++) {
        w[i] = entry_grid_width(&lb->items[from + i], cfg);
        if (w[i] > maxw) maxw = w[i];
    }

    size_t avail = (term_width > margin) ? term_width - margin : 1;
    size_t max_cols = (avail + gap) / (maxw + gap);
    if (max_cols < 1) max_cols = 1;
    if (max_cols > n) max_cols = n;

    size_t cols = 1, rows = n;
    size_t *colw = (size_t *)malloc(sizeof(size_t) * max_cols);

    for (size_t try_cols = max_cols; try_cols >= 1; try_cols--) {
        size_t try_rows = (n + try_cols - 1) / try_cols;
        size_t total = 0;
        for (size_t c = 0; c < try_cols; c++) {
            size_t cw = 0;
            for (size_t r = 0; r < try_rows; r++) {
                size_t idx = c * try_rows + r;
                if (idx < n && w[idx] > cw) cw = w[idx];
            }
            colw[c] = cw;
            total += cw;
            if (c + 1 < try_cols) total += gap;
        }
        if (total <= avail || try_cols == 1) {
            cols = try_cols;
            rows = try_rows;
            break;
        }
    }

    for (size_t r = 0; r < rows; r++) {
        printf("  ");
        for (size_t c = 0; c < cols; c++) {
            size_t idx = c * rows + r;
            if (idx >= n) continue;
            PrintLine *pl = &lb->items[from + idx];
            bool is_mod = cfg->modules[MOD_DIFF] && pl->diff_checked && pl->modified;
            const char *namecol = is_mod             ? COL(cfg, ANSI_MODIFIED)
                                  : pl->is_symlink    ? COL(cfg, ANSI_SYMLINK)
                                  : pl->is_dir        ? COL(cfg, ANSI_DIR)
                                                       : COL(cfg, ANSI_FILE);
            printf("%s%s%s%s", namecol, pl->name, pl->is_dir ? "/" : "", RST(cfg));
            if (is_mod) printf(" [m]");

            bool last_in_row = (c + 1 == cols) || (idx + rows >= n);
            if (!last_in_row) {
                size_t pad = colw[c] - w[idx];
                for (size_t s = 0; s < pad; s++) putchar(' ');
                for (size_t s = 0; s < gap; s++) putchar(' ');
            }
        }
        putchar('\n');
    }

    free(w);
    free(colw);
}

/* Dispatches [from,to) to either the packed grid or the existing
 * one-per-line (-o column aware) rendering. */
static void print_block(const LineBuf *lb, size_t from, size_t to, const MeasuredColumns *mc,
                         const Config *cfg, size_t col_start, bool grid_mode, size_t term_width) {
    if (from >= to) return;
    if (grid_mode) {
        print_grid(lb, from, to, cfg, term_width);
    } else {
        for (size_t i = from; i < to; i++) print_ls_line(lb, mc, cfg, i, col_start);
    }
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

    /* Packed multi-column grid, like plain `ls`, only when there's no
     * per-entry data to show (an -o column would make a packed grid
     * unreadable) and stdout is actually a terminal -- piped output
     * always stays one-per-line, the same way real `ls` only grids
     * when writing to a tty. */
    bool grid_mode = !mc.any_module && isatty(STDOUT_FILENO);
    size_t term_width = grid_mode ? terminal_width() : 0;

    printf("%s%s%s\n", COL(cfg, ANSI_DIR), display_path, RST(cfg));

    bool combined = cfg->sort.set && cfg->sort.combined;

    if (combined) {
        print_block(&lb, 0, lb.n, &mc, cfg, col_start, grid_mode, term_width);
    } else {
        if (ndirs > 0) {
            printf("%s[Folders]%s\n", COL(cfg, ANSI_DIR), RST(cfg));
            print_block(&lb, 0, ndirs, &mc, cfg, col_start, grid_mode, term_width);
        }
        if (lb.n > ndirs) {
            printf("%s[Files]%s\n", COL(cfg, ANSI_FILE), RST(cfg));
            if (n_buckets > 0) {
                for (size_t bi = 0; bi < n_buckets; bi++) {
                    printf("  %s[%s]%s\n", COL(cfg, ANSI_EXT), bucket_names[bi], RST(cfg));
                    size_t seg_start = bucket_at[bi];
                    size_t seg_end = (bi + 1 < n_buckets) ? bucket_at[bi + 1] : lb.n;
                    print_block(&lb, seg_start, seg_end, &mc, cfg, col_start, grid_mode, term_width);
                }
            } else {
                print_block(&lb, ndirs, lb.n, &mc, cfg, col_start, grid_mode, term_width);
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
