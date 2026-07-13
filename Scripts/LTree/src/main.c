/*
 * main.c -- ltree: blazing-fast recursive directory tree, line/char
 * counter, and JSON tree exporter. Zero external dependencies --
 * libc + POSIX only (dirent, mmap, fnmatch), so it builds the same on
 * any distro, any libc (glibc/musl), no vendored deps to rot.
 *
 * See docs/architecture.md for the module map. In one paragraph: we
 * walk the filesystem exactly once (scan.c), building an in-memory
 * Node tree with every stat/line/char/hash field already filled in.
 * Everything downstream -- the aligned tree view (render_tree.c), the
 * FILES-by-extension summary (render_files.c), JSON export (json.c),
 * --save-output (save.c), and -o DIFF (diff.c) -- is just a different
 * way of reading that same tree.
 *
 * Build: see flake.nix, or README.md for the plain-gcc one-liner
 * (every .c file under src/, compiled together -- no per-file build).
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

#include "config.h"
#include "node.h"
#include "scan.h"
#include "exttable.h"
#include "gitignore.h"
#include "hash.h"
#include "json.h"
#include "diff.h"
#include "save.h"
#include "render_tree.h"
#include "render_files.h"
#include "debug.h"

static void print_usage(const char *prog) {
    printf(
        "usage: %s [path] [options]\n"
        "\n"
        "  -j                    output JSON instead of a tree view\n"
        "  -d                    list directories only\n"
        "  -L <n>                max depth to descend (like tree -L), also -L<n>\n"
        "  -o <MODULES>          comma-separated, any order:\n"
        "                          LINES, CHARS, TOTAL, FILES,\n"
        "                          PERMISSIONS, SIZE, DATE, EXT, HASH, DIFF, DEBUG\n"
        "  -o A                  every module at once (also -oA). Can't be combined\n"
        "                        with other module names -- it's already all of them.\n"
        "  --exclude <list>      comma-separated names/globs to skip, quote\n"
        "                        entries with spaces: --exclude \"build,*.pyc\"\n"
        "  --gitignore           also exclude what the scan root's .gitignore\n"
        "                        would (composes with --exclude)\n"
        "  --cryptographic       -o HASH / -o DIFF use SHA-256 instead of the\n"
        "                        default xxHash64\n"
        "  --save-output[=DIR]   write a JSON snapshot to DIR/.ltree/ (default:\n"
        "                        <path>/.ltree/); filename is a local\n"
        "                        dd-mm-yyyy_hh:mm:ss timestamp\n"
        "  --no-colour           disable ANSI colour (also --no-color)\n"
        "  -h, --help            this help\n"
        "\n"
        "  LINES/CHARS/PERMISSIONS/SIZE/DATE/HASH each print as their own\n"
        "  aligned [X: ...] column per entry (dirs aggregate LINES/CHARS/SIZE\n"
        "  over their DIRECT children; PERMISSIONS/DATE are the entry's own).\n"
        "  EXT toggles showing file extensions in the tree (hidden by default).\n"
        "  DIFF compares against the newest .ltree snapshot, marking changed\n"
        "  entries red with a trailing [m]. TOTAL and FILES are summary\n"
        "  sections appended at the end.\n"
        "  DEBUG prints a hyper-detailed run report (timing, peak RSS, heap\n"
        "  arena breakdown, page faults, throughput, ...) appended after TOTAL.\n",
        prog);
}

int main(int argc, char **argv) {
    DebugTimer dtimer;
    debug_timer_mark_start(&dtimer);

    Config cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.max_depth = -1;
    cfg.hash_algo = HASH_ALGO_NONE;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-j") == 0) {
            cfg.json = true;
        } else if (strcmp(a, "-d") == 0) {
            cfg.dirs_only = true;
        } else if (strcmp(a, "--no-colour") == 0 || strcmp(a, "--no-color") == 0) {
            cfg.no_colour = true;
        } else if (strcmp(a, "--gitignore") == 0) {
            cfg.use_gitignore = true;
        } else if (strcmp(a, "--cryptographic") == 0) {
            cfg.cryptographic = true;
        } else if (strcmp(a, "--save-output") == 0) {
            cfg.save_output = true;
        } else if (strncmp(a, "--save-output=", 14) == 0) {
            cfg.save_output = true;
            cfg.save_output_dir = strdup(a + 14);
        } else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strncmp(a, "-L", 2) == 0 && strlen(a) > 2) {
            cfg.max_depth = atoi(a + 2);
        } else if (strcmp(a, "-L") == 0) {
            if (i + 1 < argc) cfg.max_depth = atoi(argv[++i]);
        } else if (strcmp(a, "-o") == 0 || (strncmp(a, "-o", 2) == 0 && strlen(a) > 2)) {
            char *val = (strcmp(a, "-o") == 0) ? (i + 1 < argc ? strdup(argv[++i]) : NULL)
                                                : strdup(a + 2);
            if (val) {
                /* -oA / -o A means "every module" and must stand alone --
                 * it's already everything, so "-oA,DEBUG" either means
                 * nothing extra or is a typo for a specific subset the
                 * caller actually wanted. Reject it instead of silently
                 * doing something the flags don't literally say. */
                char *scan = strdup(val);
                int ntok = 0, has_all = 0;
                char *stok = strtok(scan, ",");
                while (stok) {
                    ntok++;
                    if (strcasecmp(stok, "A") == 0) has_all = 1;
                    stok = strtok(NULL, ",");
                }
                free(scan);

                if (has_all && ntok > 1) {
                    fprintf(stderr,
                            "error: -o A selects every module by itself and can't be "
                            "combined with other module names (got '-o %s')\n", val);
                    free(val);
                    print_usage(argv[0]);
                    return 1;
                } else if (has_all) {
                    cfg.o_lines = cfg.o_chars = cfg.o_total = cfg.o_files = true;
                    cfg.o_perm  = cfg.o_size  = cfg.o_date  = cfg.o_ext   = true;
                    cfg.o_hash  = cfg.o_diff  = cfg.o_debug = true;
                } else {
                    char *tok = strtok(val, ",");
                    while (tok) {
                        if      (strcasecmp(tok, "LINES") == 0)       cfg.o_lines = true;
                        else if (strcasecmp(tok, "CHARS") == 0)       cfg.o_chars = true;
                        else if (strcasecmp(tok, "TOTAL") == 0)       cfg.o_total = true;
                        else if (strcasecmp(tok, "FILES") == 0)       cfg.o_files = true;
                        else if (strcasecmp(tok, "PERMISSIONS") == 0) cfg.o_perm = true;
                        else if (strcasecmp(tok, "SIZE") == 0)        cfg.o_size = true;
                        else if (strcasecmp(tok, "DATE") == 0)        cfg.o_date = true;
                        else if (strcasecmp(tok, "EXT") == 0)         cfg.o_ext = true;
                        else if (strcasecmp(tok, "HASH") == 0)        cfg.o_hash = true;
                        else if (strcasecmp(tok, "DIFF") == 0)        cfg.o_diff = true;
                        else if (strcasecmp(tok, "DEBUG") == 0)       cfg.o_debug = true;
                        else fprintf(stderr, "warning: unknown -o module '%s'\n", tok);
                        tok = strtok(NULL, ",");
                    }
                }
                free(val);
            }
        } else if (strcmp(a, "--exclude") == 0) {
            if (i + 1 < argc) {
                char **list; size_t n;
                parse_exclude_list(argv[++i], &list, &n);
                cfg.excludes = list;
                cfg.nexcludes = n;
            }
        } else if (strncmp(a, "--exclude=", 10) == 0) {
            char **list; size_t n;
            parse_exclude_list(a + 10, &list, &n);
            cfg.excludes = list;
            cfg.nexcludes = n;
        } else if (a[0] == '-' && strlen(a) > 1) {
            fprintf(stderr, "unknown option: %s\n", a);
            print_usage(argv[0]);
            return 1;
        } else {
            cfg.path = strdup(a);
        }
    }

    if (!cfg.path) cfg.path = strdup(".");

    struct stat st;
    if (stat(cfg.path, &st) != 0 || !S_ISDIR(st.st_mode)) {
        fprintf(stderr, "invalid path: %s\n", cfg.path);
        return 1;
    }

    /* ---- resolve hashing: DIFF forces the snapshot's own algorithm,
     * regardless of --cryptographic (see docs/plan.md) ---- */
    HashAlgo desired_algo = cfg.cryptographic ? HASH_ALGO_CRYPTO : HASH_ALGO_FAST;
    char *snapshot_path = NULL;
    bool diff_available = false;

    if (cfg.o_diff) {
        char *snapdir = ltree_snapshot_dir(&cfg);
        snapshot_path = find_latest_snapshot(snapdir);
        free(snapdir);
        if (snapshot_path) {
            HashAlgo snap_algo = diff_peek_algo(snapshot_path);
            if (snap_algo != HASH_ALGO_NONE) desired_algo = snap_algo;
            diff_available = true;
        }
    }

    bool need_hash = cfg.o_hash || cfg.save_output || cfg.o_diff;
    cfg.hash_algo = need_hash ? desired_algo : HASH_ALGO_NONE;

    /* ---- optional .gitignore, composed with --exclude ---- */
    GitTable gt;
    memset(&gt, 0, sizeof(gt));
    if (cfg.use_gitignore) gitignore_load(cfg.path, &gt);

    /* ---- the one filesystem walk ---- */
    Node *root = node_new(cfg.path, true);
    root->mtime = st.st_mtime;
    root->mode = st.st_mode;
    Totals totals = {0, 0, 0, 0};
    ExtTable ext;
    exttable_init(&ext);

    debug_timer_mark_scan_start(&dtimer);
    build_tree(root, cfg.path, "", 0, &cfg, cfg.use_gitignore ? &gt : NULL, &totals, &ext);
    debug_timer_mark_scan_end(&dtimer);
    for (size_t i = 0; i < root->nchildren; i++) {
        root->lines += root->children[i]->lines;
        root->chars += root->children[i]->chars;
        root->size_bytes += root->children[i]->size_bytes;
    }

    /* Root is never anyone's child, so build_tree's recursive
     * hash_combine_children() call (which only fires when a directory
     * is being attached to its parent) never runs for it. Without this,
     * root->hash stays all-zero/absent even though every child and
     * grandchild has a correct combined hash -- do the same combine
     * here, once, for the top of the tree. */
    if (need_hash && root->nchildren > 0) {
        char **names = (char **)malloc(sizeof(char *) * root->nchildren);
        uint8_t (*hashes)[HASH_MAX_BYTES] =
            malloc(sizeof(uint8_t[HASH_MAX_BYTES]) * root->nchildren);
        uint8_t *lens = (uint8_t *)malloc(root->nchildren);
        for (size_t i = 0; i < root->nchildren; i++) {
            names[i] = root->children[i]->name;
            memcpy(hashes[i], root->children[i]->hash, HASH_MAX_BYTES);
            lens[i] = root->children[i]->hash_len;
        }
        hash_combine_children(cfg.hash_algo, names, hashes, lens,
                               root->nchildren, root->hash, &root->hash_len);
        free(names); free(hashes); free(lens);
    }

    if (cfg.o_diff && snapshot_path) diff_apply(snapshot_path, root);

    DebugStats dbg_stats;
    const DebugStats *dbg = NULL;
    if (cfg.o_debug) {
        debug_collect(&dbg_stats, &dtimer, root, &totals, &cfg);
        dbg = &dbg_stats;
    }

    /* ---- output ---- */
    if (cfg.json) {
        print_json(root, cfg.path, &totals, &ext, &cfg, dbg);
    } else {
        print_tree_view(root, cfg.path, &cfg, &totals, diff_available, dbg);
        if (cfg.o_files) print_files_summary(&ext, &cfg);
    }

    if (cfg.save_output) save_output(root, cfg.path, &totals, &ext, &cfg);

    node_free(root);
    exttable_free(&ext);
    gitignore_free(&gt);
    for (size_t i = 0; i < cfg.nexcludes; i++) free(cfg.excludes[i]);
    free(cfg.excludes);
    free(cfg.path);
    free(cfg.save_output_dir);
    free(snapshot_path);
    return 0;
}
