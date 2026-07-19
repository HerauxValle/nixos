/* &desc: "CLI entry point: parses every flag into a Config, resolves which hash algorithm the run needs, runs the one filesystem walk (--live wires up streaming hooks; default doesn't), then dispatches to JSON, the buffered or already-streamed tree view, or the default non-recursive ls view." */
/*
 * main.c -- ltree: blazing-fast recursive directory tree, line/char
 * counter, and JSON tree exporter. Zero external dependencies --
 * libc + POSIX only (dirent, mmap, fnmatch), so it builds the same on
 * any distro, any libc (glibc/musl), no vendored deps to rot.
 *
 * See docs/architecture.md for the module map. In one paragraph: we
 * walk the filesystem exactly once (scan.c), building an in-memory
 * Node tree with every stat/line/char/hash field already filled in.
 * By default, everything downstream -- the recursive tree view
 * (render_tree.c), the default ls-mode listing (render_ls.c), the
 * FILES-by-extension summary (render_files.c), JSON export (json.c),
 * --save-output (save.c), and -o DIFF (diff.c) -- is just a different
 * way of reading the complete, already-built tree once the walk
 * finishes. --live is the one exception: it streams -o TREE's output
 * via three hooks fired during the walk itself (render_tree.c),
 * printing top-down with fixed-width columns instead of waiting for
 * (and whole-tree-aligning against) the complete tree.
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
#include <unistd.h>
#include <limits.h>
#include <libgen.h>

#include "core/config.h"
#include "core/modules.h"
#include "core/node.h"
#include "sort/sortmodes.h"
#include "scan/scan.h"
#include "scan/exttable.h"
#include "scan/gitignore.h"
#include "hash/hash.h"
#include "io/json.h"
#include "io/diff.h"
#include "io/save.h"
#include "render/render_tree.h"
#include "render/render_ls.h"
#include "render/render_files.h"
#include "render/columns.h"
#include "render/colors.h"
#include "debug/debug.h"
#include "util/spinner.h"

/* Whether module `id` is worth actually computing this run: named in -o,
 * forced by --save-output (always the full snapshot), or -- the gap this
 * closes -- named in a --stdout exclusive/inclusive filter even without a
 * matching -o (see docs/json-schema.md). Deliberately does NOT fire for
 * plain -j with no --stdout filter: that's the pre-existing, documented
 * "only what --stdout/-o/--save-output actually asked for" contract, not a
 * blanket "-j means everything." */
/* Splits a --desc/-D format string on the literal "..." into a search
 * prefix (everything before, e.g. `&desc: "`) and a closing suffix
 * (everything after, e.g. `"`). No special-casing of "the character
 * touching the dots" is needed beyond this plain split -- it falls out
 * naturally, since the prefix already ends at whatever character
 * immediately precedes "..." and the suffix starts at whatever
 * immediately follows it. Both sides must be non-empty (an empty prefix
 * would match everywhere; an empty suffix would capture nothing every
 * time), so `&desc: "..."` and `&description: *...*` both work but a bare
 * `...` or a format ending right at "..." doesn't. Returns false (leaving
 * out_prefix/out_suffix untouched) on anything malformed. */
static bool desc_parse_format(const char *format, char **out_prefix, char **out_suffix) {
    const char *dots = strstr(format, "...");
    if (!dots) return false;
    size_t prefix_len = (size_t)(dots - format);
    size_t suffix_len = strlen(dots + 3);
    if (prefix_len == 0 || suffix_len == 0) return false;
    *out_prefix = strndup(format, prefix_len);
    *out_suffix = strdup(dots + 3);
    return true;
}

static bool field_wanted(const Config *cfg, ModuleId id) {
    if (cfg->modules[id]) return true;
    if (cfg->save_output) return true;
    if (cfg->stdout_filter != STDOUT_FILTER_NONE) return json_key_allowed(cfg, id);
    return false;
}

/* Enables every comma-separated module named in `val` (mutated by
 * strtok -- pass a caller-owned copy). Unknown names warn and are
 * otherwise ignored, same leniency as every other -o path. Shared by
 * plain "-o <MODULES>"/"-oLINES,CHARS" and -oO's optional module arg. */
static void enable_modules_from_list(Config *cfg, char *val) {
    char *tok = strtok(val, ",");
    while (tok) {
        const ModuleDef *def = module_lookup(tok);
        if (def) {
            cfg->modules[def->id] = true;
            cfg->order_seen[cfg->n_order_seen++] = def->id;
        } else {
            fprintf(stderr, "warning: unknown -o module '%s'\n", tok);
        }
        tok = strtok(NULL, ",");
    }
}

/* -oA's exclude form: enables every module EXCEPT the ones named in
 * `val` (-oA with nothing after it enables all of them instead). */
static void enable_all_except(Config *cfg, char *val) {
    bool excluded[MOD_COUNT] = {0};
    char *tok = strtok(val, ",");
    while (tok) {
        const ModuleDef *def = module_lookup(tok);
        if (def) {
            excluded[def->id] = true;
        } else {
            fprintf(stderr, "warning: unknown -o module '%s'\n", tok);
        }
        tok = strtok(NULL, ",");
    }
    for (int m = 0; m < MOD_COUNT; m++) {
        if (excluded[m]) continue;
        cfg->modules[m] = true;
    }
}

static void help_entry(bool no_colour, const char *name, const char *color, const char *desc) {
    printf("%s%s%s\n  %s\n\n", no_colour ? "" : color, name, no_colour ? "" : ANSI_RESET, desc);
}

static void print_usage(const char *prog, bool no_colour) {
    printf("usage: %s [path] [options]\n\n", prog);

#define H(name, desc) help_entry(no_colour, name, "\x1b[1;36m", desc)
    H("-j", "output JSON instead of a tree view");
    H("-jL", "output NDJSON (one flat object per entry, path-tagged) instead\n"
             "  of -j's one nested tree -- streamable line-by-line, same --stdout\n"
             "  filtering applies");
    H("-d", "list directories only");
    H("-L <n>", "max depth to descend (like tree -L), also -L<n>. With -o TREE, limits\n"
                 "  the connector tree's depth; without it, recurses the plain\n"
                 "  [Folders]/[Files] listing per-directory instead of forcing -o TREE");
    H("-o <MODULES>", "comma-separated, any order: LINES, CHARS, TOTAL, FILES, PERMISSIONS,\n"
                       "  SIZE, DATE, EXT, HASH, DESC, DIFF, DEBUG, TREE, HIDDEN");
    H("-oA <MODULES>", "every module at once (MODULES optional -- if given, every module\n"
                        "  EXCEPT the ones named)");
    H("-oO <MODULES>", "render columns in the order you typed them in -o (MODULES optional\n"
                        "  -- also just enables them)");
    H("--exclude <list>", "comma-separated names/globs to skip, quote entries with spaces:\n"
                           "  --exclude \"build,*.pyc\"");
    H("--gitignore", "also exclude what the scan root's .gitignore would (composes with\n"
                      "  --exclude)");
    H("--cryptographic", "-o HASH / -o DIFF use SHA-256 instead of the default xxHash64");
    H("--simple-hash", "hash a bounded sample (size + first/last 64KiB) instead of the whole\n"
                        "  file for anything over 128KiB. -o DIFF/--save-output snapshots\n"
                        "  record whether this was on, so a later DIFF run always compares\n"
                        "  like-for-like regardless of its own flags");
    H("--save-output[=DIR]", "write a JSON snapshot to DIR/.ltree/ (default: <path>/.ltree/);\n"
                              "  filename is a local dd-mm-yyyy_hh:mm:ss timestamp");
    H("--no-colour", "disable ANSI colour (also --no-color)");
    H("--condense", "one [L:x C:y ...] bracket per entry instead of one bracket per active\n"
                     "  column. Either way, columns share the entry's own line for as long as\n"
                     "  they fit, wrapping to guide-indented lines beneath it once they don't");
    H("--live", "-o TREE only: stream top-down as the walk happens instead of waiting for\n"
                "  it to finish; fixed-width columns instead of whole-tree-measured ones.\n"
                "  No effect with -j");
    H("--sort <MODES>", "ls-mode only (no effect with -o TREE). One base: abc (default),\n"
                         "  birth, modified, lines, chars, types -- plus modifiers: combined,\n"
                         "  reversed");
    H("--stdout <exclusive|inclusive> <MODULES>",
      "forces JSON output (like -j) filtered to exclude or keep only the named\n"
      "  modules' JSON fields");
    H("--desc <format>", "what -o DESC searches file content for, split on the literal\n"
                          "  \"...\" (default: &desc: \"...\", matching this project's own\n"
                          "  header-comment convention) -- everything before \"...\" is the\n"
                          "  search prefix, everything after is the closing delimiter, e.g.\n"
                          "  --desc \"&description: *...*\" searches for &description: * ... *\n"
                          "  instead. Also --desc=<format>");
    H("-D <format>", "alias for --desc (NOT -d, which is dirs-only)");
    H("-h, --help", "this help");
#undef H

#define M(name, color, desc) help_entry(no_colour, name, color, desc)
    M("LINES/CHARS/PERMISSIONS/SIZE/DATE/HASH", "\x1b[1;36m",
      "each print as their own aligned [X: ...] column per entry (dirs\n"
      "  aggregate LINES/CHARS/SIZE over their DIRECT children; PERMISSIONS/DATE\n"
      "  are the entry's own)");
    M("EXT", ANSI_EXT, "toggles showing file extensions in the tree (hidden by default)");
    M("DESC", ANSI_DESC, "prints the first matching --desc marker's text as its own column,\n"
                          "  or [DESC: -] when a file has none");
    M("DIFF", ANSI_MODIFIED, "compares against the newest .ltree snapshot, marking changed\n"
                              "  entries red with a trailing [m]");
    M("TOTAL/FILES", ANSI_TOTAL, "summary sections appended at the end");
    M("DEBUG", ANSI_DEBUG, "prints a hyper-detailed run report (timing, peak RSS, heap arena\n"
                            "  breakdown, page faults, throughput, ...) appended after TOTAL");
    M("TREE", ANSI_DIR, "without it, ltree lists only `path`'s direct children, grouped into\n"
                         "  [Folders]/[Files] (like plain ls); with it, the recursive connector\n"
                         "  tree (respecting -L), whole-tree column aligned, printed once the\n"
                         "  walk finishes (see --live to stream it)");
    M("HIDDEN", ANSI_DIR, "shows dotfiles/dot-dirs (hidden by default, like ls -a)");
#undef M
}

int main(int argc, char **argv) {
    DebugTimer dtimer;
    debug_timer_mark_start(&dtimer);

    Config cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.max_depth = -1;
    cfg.hash_algo = HASH_ALGO_NONE;

    /* Pre-scan for --no-colour so it applies to --help/error usage output
     * too, regardless of where it appears relative to those on the command
     * line (the main loop below sets it again in its normal position,
     * harmlessly redundant). */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--no-colour") == 0 || strcmp(argv[i], "--no-color") == 0) {
            cfg.no_colour = true;
            break;
        }
    }

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-j") == 0) {
            cfg.json = true;
        } else if (strcmp(a, "-jL") == 0) {
            cfg.json = true;
            cfg.json_lines = true;
        } else if (strcmp(a, "-d") == 0) {
            cfg.dirs_only = true;
        } else if (strcmp(a, "--no-colour") == 0 || strcmp(a, "--no-color") == 0) {
            cfg.no_colour = true;
        } else if (strcmp(a, "--condense") == 0) {
            cfg.condense = true;
        } else if (strcmp(a, "--live") == 0) {
            cfg.live = true;
        } else if (strcmp(a, "--sort") == 0) {
            if (i + 1 < argc) {
                if (!sort_parse(argv[++i], &cfg.sort)) { print_usage(argv[0], cfg.no_colour); return 1; }
            }
        } else if (strncmp(a, "--sort=", 7) == 0) {
            if (!sort_parse(a + 7, &cfg.sort)) { print_usage(argv[0], cfg.no_colour); return 1; }
        } else if (strcmp(a, "--stdout") == 0) {
            if (i + 2 >= argc) {
                fprintf(stderr, "error: --stdout needs 'exclusive'/'inclusive' and a "
                                 "module list (--stdout exclusive TREE,LINES)\n");
                print_usage(argv[0], cfg.no_colour);
                return 1;
            }
            const char *mode = argv[++i];
            const char *list = argv[++i];
            if (strcasecmp(mode, "exclusive") == 0) cfg.stdout_filter = STDOUT_FILTER_EXCLUSIVE;
            else if (strcasecmp(mode, "inclusive") == 0) cfg.stdout_filter = STDOUT_FILTER_INCLUSIVE;
            else {
                fprintf(stderr, "error: --stdout mode must be 'exclusive' or 'inclusive', "
                                 "got '%s'\n", mode);
                print_usage(argv[0], cfg.no_colour);
                return 1;
            }
            char *copy = strdup(list);
            char *tok = strtok(copy, ",");
            while (tok) {
                const ModuleDef *def = module_lookup(tok);
                if (def) cfg.stdout_filter_keys[def->id] = true;
                else fprintf(stderr, "warning: unknown --stdout module '%s'\n", tok);
                tok = strtok(NULL, ",");
            }
            free(copy);
            cfg.json = true;
        } else if (strcmp(a, "--gitignore") == 0) {
            cfg.use_gitignore = true;
        } else if (strcmp(a, "--cryptographic") == 0) {
            cfg.cryptographic = true;
        } else if (strcmp(a, "--simple-hash") == 0) {
            cfg.simple_hash = true;
        } else if (strcmp(a, "--save-output") == 0) {
            cfg.save_output = true;
        } else if (strncmp(a, "--save-output=", 14) == 0) {
            cfg.save_output = true;
            cfg.save_output_dir = strdup(a + 14);
        } else if (strcmp(a, "--desc") == 0 || strcmp(a, "-D") == 0) {
            if (i + 1 < argc) {
                const char *format = argv[++i];
                char *prefix = NULL, *suffix = NULL;
                if (!desc_parse_format(format, &prefix, &suffix)) {
                    fprintf(stderr, "error: --desc/-D format needs \"...\" with a non-empty "
                                     "prefix and suffix around it (got '%s')\n", format);
                    print_usage(argv[0], cfg.no_colour);
                    return 1;
                }
                free(cfg.desc_prefix); free(cfg.desc_suffix);
                cfg.desc_prefix = prefix;
                cfg.desc_suffix = suffix;
            }
        } else if (strncmp(a, "--desc=", 7) == 0) {
            char *prefix = NULL, *suffix = NULL;
            if (!desc_parse_format(a + 7, &prefix, &suffix)) {
                fprintf(stderr, "error: --desc format needs \"...\" with a non-empty "
                                 "prefix and suffix around it (got '%s')\n", a + 7);
                print_usage(argv[0], cfg.no_colour);
                return 1;
            }
            free(cfg.desc_prefix); free(cfg.desc_suffix);
            cfg.desc_prefix = prefix;
            cfg.desc_suffix = suffix;
        } else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            print_usage(argv[0], cfg.no_colour);
            return 0;
        } else if (strncmp(a, "-L", 2) == 0 && strlen(a) > 2) {
            /* Depth-limited recursion. Without -o TREE spelled out
             * separately, this no longer forces the connector tree view --
             * it instead recurses the plain [Folders]/[Files] listing,
             * one block per directory (see print_ls_view_recursive and the
             * depth_limited dispatch below). With -o TREE, unchanged:
             * limits the connector tree's own depth. */
            cfg.max_depth = atoi(a + 2);
        } else if (strcmp(a, "-L") == 0) {
            if (i + 1 < argc) {
                cfg.max_depth = atoi(argv[++i]);
            }
        } else if (strcmp(a, "-o") == 0) {
            /* Plain module list: "-o LINES,CHARS". Always literal -- "A"/
             * "O" here are just (unknown) module names, not shorthand;
             * the shorthand only exists as -oA/-oO below. */
            if (i + 1 < argc) {
                char *val = strdup(argv[++i]);
                enable_modules_from_list(&cfg, val);
                free(val);
            }
        } else if (strncmp(a, "-o", 2) == 0 && strcasecmp(a + 2, "A") == 0) {
            /* Every module at once. Optionally followed by modules to
             * exclude instead -- "-oA" alone means everything, "-oA DESC"
             * means everything except DESC. */
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                char *val = strdup(argv[++i]);
                enable_all_except(&cfg, val);
                free(val);
            } else {
                for (int m = 0; m < MOD_COUNT; m++) cfg.modules[m] = true;
            }
        } else if (strncmp(a, "-o", 2) == 0 && strcasecmp(a + 2, "O") == 0) {
            /* Render -o columns in the order they were typed, across the
             * whole run. Optionally followed by more modules to enable in
             * the same breath -- "-oO HASH" enables HASH and preserves
             * typed order, same as "-oO" alone plus a separate "-o HASH". */
            cfg.o_order = true;
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                char *val = strdup(argv[++i]);
                enable_modules_from_list(&cfg, val);
                free(val);
            }
        } else if (strncmp(a, "-o", 2) == 0 && strlen(a) > 2) {
            /* -oLINES,CHARS -- modules glued directly onto -o. */
            char *val = strdup(a + 2);
            enable_modules_from_list(&cfg, val);
            free(val);
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
            print_usage(argv[0], cfg.no_colour);
            return 1;
        } else {
            cfg.path = strdup(a);
        }
    }

    /* No positional path and stdin is piped (not a terminal) -- read
     * one line from it and use that as the path, so `find . -type d |
     * head -1 | ltree` style pipelines work. A TTY stdin with no path
     * arg keeps today's "." default; fgets() failing (empty pipe)
     * falls back to "." the same way. */
    if (!cfg.path && !isatty(fileno(stdin))) {
        char buf[PATH_MAX];
        if (fgets(buf, sizeof(buf), stdin)) {
            buf[strcspn(buf, "\r\n")] = '\0';
            if (buf[0] != '\0') cfg.path = strdup(buf);
        }
    }
    if (!cfg.path) cfg.path = strdup(".");

    /* --desc/-D's default, matching this project's own `&desc: "..."`
     * header-comment convention -- only set if the user didn't already
     * pass a custom format above. */
    if (!cfg.desc_prefix) {
        cfg.desc_prefix = strdup("&desc: \"");
        cfg.desc_suffix = strdup("\"");
    }
    cfg.need_desc = field_wanted(&cfg, MOD_DESC);

    /* --sort only means anything in the ls-mode view -- tree mode
     * (-o TREE) keeps node_cmp's plain alphabetical order (see
     * docs/plan-ls-rework.md, Category 6). Warn and ignore rather than
     * error, same leniency class as an unknown -o module. */
    if (cfg.sort.set && cfg.modules[MOD_TREE]) {
        fprintf(stderr, "warning: --sort has no effect with -o TREE, ignoring\n");
        cfg.sort.set = false;
    }

    /* --live only means anything for -o TREE (ls-mode is already one
     * non-recursive directory -- nothing to stream) and is meaningless
     * with -j, which needs the complete tree before it can emit one
     * JSON value. Warn and ignore rather than error, same leniency
     * class as --sort + -o TREE above. */
    if (cfg.live && !cfg.modules[MOD_TREE]) {
        fprintf(stderr, "warning: --live has no effect without -o TREE, ignoring\n");
        cfg.live = false;
    }
    if (cfg.live && cfg.json) {
        fprintf(stderr, "warning: --live has no effect with -j, ignoring\n");
        cfg.live = false;
    }

    struct stat st;
    if (stat(cfg.path, &st) != 0 || !(S_ISDIR(st.st_mode) || S_ISREG(st.st_mode))) {
        fprintf(stderr, "invalid path: %s\n", cfg.path);
        return 1;
    }
    /* `path` naming a regular file instead of a directory: same rendering,
     * same rules, just one entry -- root becomes a synthetic single-child
     * container instead of a real directory (see the path_is_file branch
     * of the walk below), same shape print_json/print_tree_view/
     * print_ls_view already expect for a directory that happens to hold
     * exactly one file. */
    bool path_is_file = S_ISREG(st.st_mode);

    /* ---- resolve hashing: DIFF forces the snapshot's own algorithm AND
     * --simple-hash setting, regardless of --cryptographic/--simple-hash
     * on this run (see docs/plan.md) -- comparing a full hash against a
     * sampled one would show every file as modified. ---- */
    HashAlgo desired_algo = cfg.cryptographic ? HASH_ALGO_CRYPTO : HASH_ALGO_FAST;
    char *snapshot_path = NULL;
    bool diff_available = false;

    if (cfg.modules[MOD_DIFF]) {
        char *snapdir = ltree_snapshot_dir(&cfg);
        snapshot_path = find_latest_snapshot(snapdir);
        free(snapdir);
        if (snapshot_path) {
            bool snap_simple_hash = false;
            HashAlgo snap_algo = diff_peek_algo(snapshot_path, &snap_simple_hash);
            if (snap_algo != HASH_ALGO_NONE) {
                desired_algo = snap_algo;
                cfg.simple_hash = snap_simple_hash;
            }
            diff_available = true;
        }
    }

    bool need_hash = field_wanted(&cfg, MOD_HASH) || cfg.modules[MOD_DIFF];
    cfg.hash_algo = need_hash ? desired_algo : HASH_ALGO_NONE;

    /* ---- optional .gitignore, composed with --exclude (meaningless for
     * a single named file -- you already named exactly what you want) ---- */
    GitTable gt;
    memset(&gt, 0, sizeof(gt));
    if (cfg.use_gitignore && !path_is_file) gitignore_load(cfg.path, &gt);

    /* ---- the one filesystem walk ---- */
    Node *root = node_new(path_is_file ? "." : cfg.path, true);
    root->mtime = st.st_mtime;
    root->btime = fetch_btime(cfg.path, st.st_mtime);
    /* path_is_file: root is a synthetic wrapper, not a real directory --
     * `st` is the FILE's own stat, so reusing its raw mode bits here would
     * mislabel them as a directory's ("drw-r--r--"). A plain, conventional
     * dir mode reads correctly instead; nothing real depends on this
     * value (root's own row never prints in ls/tree views, only as
     * JSON's wrapper "tree" object). */
    root->mode = path_is_file ? (S_IFDIR | 0755) : st.st_mode;
    Totals totals = {0, 0, 0, 0};
    ExtTable ext;
    exttable_init(&ext);

    /* Without -o TREE and without -L, the terminal view is the
     * non-recursive [Folders]/[Files] listing (see
     * docs/plan-ls-rework.md, Category 2) -- one level is all it'll
     * ever show, so don't walk deeper than that. -L given without -o
     * TREE instead recurses that same listing per-directory up to its
     * depth (print_ls_view_recursive below), so max_depth stays
     * whatever -L set. -j stays fully recursive regardless of -o TREE:
     * JSON is a data export whose existing contract (full tree,
     * -L-limited) predates -o TREE and isn't a "view" this flag is
     * meant to change. */
    bool depth_limited = cfg.max_depth >= 0;
    if (!cfg.json && !cfg.modules[MOD_TREE] && !depth_limited) cfg.max_depth = 0;

    /* --live is the only case that streams -o TREE's output during
     * the walk (see render/render_tree.h) -- the default is fully
     * buffered, whole-tree-aligned, same as every other view. Nothing to
     * stream for a single already-known file either. */
    bool stream_tree = cfg.live && !path_is_file;

    /* Animated "still working" indicator (see util/spinner.h) -- a no-op
     * unless stderr is a tty. Started before tree_live_start() so --live's
     * header print is itself wrapped by the spinner the same way every
     * later streamed line is. spinner_stop() below (right after the walk
     * finishes) covers both modes: for the buffered views it clears the
     * line before anything prints; for --live it clears the last redrawn
     * frame before print_summary_tail(). */
    spinner_start(cfg.no_colour);
    if (stream_tree) tree_live_start(cfg.path, &cfg);

    debug_timer_mark_scan_start(&dtimer);
    if (path_is_file) {
        char pathcopy[4096];
        snprintf(pathcopy, sizeof(pathcopy), "%s", cfg.path);
        Node *filenode = node_new(basename(pathcopy), false);
        filenode->mode = st.st_mode;
        filenode->mtime = st.st_mtime;
        filenode->btime = fetch_btime(cfg.path, st.st_mtime);

        long lines = 0, chars = 0;
        uint8_t hbuf[HASH_MAX_BYTES] = {0}; uint8_t hlen = 0;
        char *desc = NULL;
        scan_single_file(cfg.path, &cfg, &lines, &chars, hbuf, &hlen, &desc);
        filenode->lines = lines;
        filenode->chars = chars;
        filenode->size_bytes = st.st_size;
        memcpy(filenode->hash, hbuf, HASH_MAX_BYTES);
        filenode->hash_len = hlen;
        filenode->desc = desc;

        totals.files = 1;
        totals.lines = lines;
        totals.chars = chars;
        exttable_add(&ext, file_ext(filenode->name), lines, chars);

        node_add_child(root, filenode);
    } else {
        build_tree(root, cfg.path, "", 0, &cfg, cfg.use_gitignore ? &gt : NULL, &totals, &ext,
                   stream_tree ? tree_live_on_dir_measure : NULL,
                   stream_tree ? tree_live_on_entry_ready : NULL,
                   stream_tree ? tree_live_on_dir_done : NULL,
                   NULL);
    }
    debug_timer_mark_scan_end(&dtimer);
    if (stream_tree) tree_live_end();
    spinner_stop();
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

    if (cfg.modules[MOD_DIFF] && snapshot_path) diff_apply(snapshot_path, root);

    DebugStats dbg_stats;
    const DebugStats *dbg = NULL;
    if (cfg.modules[MOD_DEBUG]) {
        debug_collect(&dbg_stats, &dtimer, root, &totals, &cfg);
        dbg = &dbg_stats;
    }

    /* ---- output ---- */
    if (cfg.json) {
        if (cfg.json_lines) print_json_lines(root, cfg.path, &totals, &ext, &cfg, dbg);
        else print_json(root, cfg.path, &totals, &ext, &cfg, dbg);
    } else if (stream_tree) {
        /* Every directory's block already printed during the scan
         * (tree_live_on_dir_measure/on_entry_ready, wired up as
         * build_tree's hooks above) -- only the FILES:/TOTAL:/DEBUG:/
         * DIFF-note tail, which needs the complete tree, is still
         * outstanding. */
        if (cfg.modules[MOD_FILES]) print_files_summary(&ext, &cfg);
        print_summary_tail(&cfg, &totals, diff_available, dbg);
    } else if (cfg.modules[MOD_TREE]) {
        print_tree_view(root, cfg.path, &cfg, &totals, diff_available, dbg);
        if (cfg.modules[MOD_FILES]) print_files_summary(&ext, &cfg);
    } else if (depth_limited) {
        print_ls_view_recursive(root, cfg.path, &cfg, &totals, diff_available, dbg);
        if (cfg.modules[MOD_FILES]) print_files_summary(&ext, &cfg);
    } else {
        print_ls_view(root, cfg.path, &cfg, &totals, diff_available, dbg);
        if (cfg.modules[MOD_FILES]) print_files_summary(&ext, &cfg);
    }

    if (cfg.save_output) save_output(root, cfg.path, &totals, &ext, &cfg);

    node_free(root);
    exttable_free(&ext);
    gitignore_free(&gt);
    for (size_t i = 0; i < cfg.nexcludes; i++) free(cfg.excludes[i]);
    free(cfg.excludes);
    free(cfg.path);
    free(cfg.save_output_dir);
    free(cfg.desc_prefix);
    free(cfg.desc_suffix);
    free(snapshot_path);
    return 0;
}
