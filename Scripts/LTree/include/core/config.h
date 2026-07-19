/* &desc: "Defines the Config struct -- the fully-parsed command line (modules[] array, sort spec, every other flag) passed by const pointer to every module that needs to read a flag, and the HashAlgo enum." */
/* config.h -- the parsed command line, in one place. Every module
 * that needs a flag takes `const Config *cfg` rather than growing its
 * own globals; main.c is the only place that ever writes to it. */
#ifndef LTREE_CONFIG_H
#define LTREE_CONFIG_H

#include <stdbool.h>
#include <stddef.h>
#include "core/modules.h"
#include "sort/sortmodes.h"

typedef enum {
    HASH_ALGO_NONE = 0,
    HASH_ALGO_FAST,     /* xxHash64 -- default, non-cryptographic       */
    HASH_ALGO_CRYPTO    /* SHA-256  -- via --cryptographic               */
} HashAlgo;

typedef struct {
    char   *path;             /* positional arg, defaults to "."         */

    bool    json;             /* -j / -jL                                */
    bool    json_lines;       /* -jL -- NDJSON (one flat object per entry,
                                * plus tagged total/by_extension/debug
                                * lines) instead of -j's one nested tree   */
    bool    dirs_only;        /* -d                                      */
    int     max_depth;        /* -L <n>, -1 = unlimited                  */
    bool    no_colour;        /* --no-colour / --no-color                */
    /* --condense -- one [L:x C:y ...] bracket per entry instead of one
     * bracket per active column. Without it, columns_print_line() packs
     * columns onto the entry's own line for as long as they fit, then
     * wraps to guide-indented continuation lines one column at a time
     * once something doesn't (see columns.c) -- there used to be a
     * separate --condense wrap mode for that overflow behavior, folded
     * into the unconditional default instead since it's what every
     * mode needs regardless of --condense. */
    bool    condense;
    SortSpec sort;            /* --sort, ls-mode only (see sort/sortmodes.h) */
    bool    live;             /* --live -- -o TREE only. Streams top-down as
                                * the walk happens, fixed-width columns instead
                                * of the default's whole-tree-measured ones
                                * (see render/render_tree.h). */

    /* -o MODULES -- one bool per ModuleId, see core/modules.h. Replaces
     * what used to be 11 hand-written bool fields (o_lines, o_chars, ...);
     * every module this run enabled is modules[MOD_*] == true. */
    bool     modules[MOD_COUNT];
    bool     o_order;             /* -o O / -oO -- its own standalone -o
                                    * token (like -o A): render columns in
                                    * the order they were typed across
                                    * every -o passed this run, instead of
                                    * MODULE_TABLE's fixed order. NOT a
                                    * modifier combinable with a module
                                    * list in the same token.              */
    ModuleId order_seen[MOD_COUNT]; /* -o argument order, filled regardless
                                      * of whether -o O/-oO was also passed,
                                      * so it can appear before or after the
                                      * module-listing -o's in the same run */
    int      n_order_seen;

    char  **excludes;         /* --exclude, parsed name/glob list         */
    size_t  nexcludes;

    bool    use_gitignore;    /* --gitignore                             */
    bool    cryptographic;    /* --cryptographic                          */
    bool    simple_hash;      /* --simple-hash -- hash a bounded sample
                                * (size + first/last 64KiB) instead of the
                                * whole file for anything past 128KiB, same
                                * algorithm either way (see hash/hash.h and
                                * scan/scan.c's hash_simple_or_full())      */

    bool    save_output;      /* --save-output[=DIR]                      */
    char   *save_output_dir;  /* NULL = use `path`                        */

    /* Resolved once in main.c before scanning starts (NONE unless -o
     * HASH, --save-output, or -o DIFF actually need one -- see
     * docs/plan.md for why DIFF can override --cryptographic). */
    HashAlgo hash_algo;

    /* -o DESC / --desc <format> / -D <format> -- search each file for a
     * marker and extract the text between two delimiters. `format`
     * defaults to `&desc: "..."` (this project's own header-comment
     * convention -- see docs/plan-hash-desc-spinner.md) and is split once
     * at startup on the literal "..." into desc_prefix (everything
     * before, e.g. `&desc: "`) and desc_suffix (everything after, e.g.
     * `"`) -- both malloc'd, both always non-NULL/non-empty once parsing
     * succeeds. need_desc is resolved once like hash_algo (see
     * field_wanted() in main.c). */
    char    *desc_prefix;
    char    *desc_suffix;
    bool     need_desc;
} Config;

#endif
