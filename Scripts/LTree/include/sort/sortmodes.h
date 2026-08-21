/* &desc: "Declares SortSpec/sort_parse/sort_nodes, --sort's ls-mode-only mode parsing (abc/birth/modified/lines/chars/types plus combined/reversed modifiers) and qsort comparator." */
/* sortmodes.h -- --sort parsing + the qsort comparator it drives.
 * ls-mode only (render/render_ls.c) -- tree mode keeps node_cmp's
 * plain case-insensitive alphabetical order, see
 * docs/plan-ls-rework.md, Category 6. */
#ifndef LTREE_SORTMODES_H
#define LTREE_SORTMODES_H

#include <stdbool.h>
#include <stddef.h>

/* Forward-declared, not #include "core/node.h" -- node.h pulls in
 * hash.h which pulls in config.h, and config.h includes this header
 * (for the Config.sort field), so a full include here would cycle
 * back before HashAlgo/etc. are defined. An opaque pointer type is
 * all a function prototype needs. */
typedef struct Node Node;

typedef enum {
    SORT_ABC,       /* default: case-insensitive alphabetical           */
    SORT_BIRTH,     /* creation time, oldest first                      */
    SORT_MODIFIED,  /* last-modified time, oldest first                 */
    SORT_LINES,     /* line count, fewest first                         */
    SORT_CHARS,     /* char count, fewest first                         */
    SORT_TYPES      /* bucketed by extension, alphabetical               */
} SortBaseMode;

typedef struct {
    bool         set;        /* --sort was passed at all                */
    SortBaseMode base;
    bool         combined;   /* don't split Folders/Files -- one flat list */
    bool         reversed;   /* flip whatever ordering `base` produces  */
} SortSpec;

/* Parses --sort's comma-separated argument (e.g. "abc,reversed") into
 * `out`. Base modes (abc/birth/modified/lines/chars/types) are
 * mutually exclusive; `combined`/`reversed` are modifiers that can
 * combine with any one base. Prints a usage error and returns false on
 * a base-mode conflict; unknown tokens warn (like -o) and are skipped,
 * not fatal. `combined` is dropped (with a warning) when paired with
 * `types`, since types already has its own grouping. */
bool sort_parse(const char *arg, SortSpec *out);

/* Sorts `arr[0..n)` (an array of Node* pointers, e.g. a slice of a
 * Node's ->children) in place per `spec`. */
void sort_nodes(Node **arr, size_t n, const SortSpec *spec);

#endif
