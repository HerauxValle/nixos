/* &desc: "Defines the Config struct -- the fully-parsed command line (modules[] array, sort spec, --stdout filter, every other flag) passed by const pointer to every module that needs to read a flag, and the HashAlgo enum." */
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

    bool    json;             /* -j                                      */
    bool    dirs_only;        /* -d                                      */
    int     max_depth;        /* -L <n>, -1 = unlimited                  */
    bool    no_colour;        /* --no-colour / --no-color                */
    bool    condense;         /* --condense -- one [L:x C:y ...] bracket
                                * instead of one bracket per column       */
    SortSpec sort;            /* --sort, ls-mode only (see sort/sortmodes.h) */

    /* --stdout exclusive|inclusive <MODULES> -- forces JSON (like -j)
     * filtered to a subset of top-level/per-entry keys. Module names
     * map to JSON field names in io/json.c's json_key_allowed(); TREE
     * means the whole "tree" key, not a per-entry field. */
    enum { STDOUT_FILTER_NONE, STDOUT_FILTER_EXCLUSIVE, STDOUT_FILTER_INCLUSIVE }
            stdout_filter;
    bool    stdout_filter_keys[MOD_COUNT];

    /* -o MODULES -- one bool per ModuleId, see core/modules.h. Replaces
     * what used to be 11 hand-written bool fields (o_lines, o_chars, ...);
     * every module this run enabled is modules[MOD_*] == true. */
    bool     modules[MOD_COUNT];
    bool     o_order;             /* -o ...,O -- render columns in the
                                    * order they were typed in -o, instead
                                    * of MODULE_TABLE's fixed order        */
    ModuleId order_seen[MOD_COUNT]; /* -o argument order, filled regardless
                                      * of o_order so O can be added after
                                      * other tokens in the same list      */
    int      n_order_seen;

    char  **excludes;         /* --exclude, parsed name/glob list         */
    size_t  nexcludes;

    bool    use_gitignore;    /* --gitignore                             */
    bool    cryptographic;    /* --cryptographic                          */

    bool    save_output;      /* --save-output[=DIR]                      */
    char   *save_output_dir;  /* NULL = use `path`                        */

    /* Resolved once in main.c before scanning starts (NONE unless -o
     * HASH, --save-output, or -o DIFF actually need one -- see
     * docs/plan.md for why DIFF can override --cryptographic). */
    HashAlgo hash_algo;
} Config;

#endif
