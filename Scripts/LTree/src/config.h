/* config.h -- the parsed command line, in one place. Every module
 * that needs a flag takes `const Config *cfg` rather than growing its
 * own globals; main.c is the only place that ever writes to it. */
#ifndef LTREE_CONFIG_H
#define LTREE_CONFIG_H

#include <stdbool.h>
#include <stddef.h>

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

    /* -o MODULES */
    bool    o_lines;
    bool    o_chars;
    bool    o_total;
    bool    o_files;
    bool    o_perm;
    bool    o_size;
    bool    o_date;
    bool    o_ext;
    bool    o_hash;
    bool    o_diff;

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
