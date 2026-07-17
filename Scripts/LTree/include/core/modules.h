/* modules.h -- the single source of truth for what an -o token means.
 * main.c's CLI parser and every renderer read this table instead of
 * each keeping its own hand-written module list/switch (see
 * docs/plan-ls-rework.md, Category 0, for the duplication this
 * replaced). */
#ifndef LTREE_MODULES_H
#define LTREE_MODULES_H

typedef enum {
    MOD_LINES, MOD_CHARS, MOD_PERM, MOD_SIZE, MOD_DATE, MOD_EXT, MOD_HASH,
    MOD_TOTAL, MOD_FILES, MOD_DEBUG,
    MOD_DIFF,
    MOD_TREE, MOD_HIDDEN,
    MOD_COUNT
} ModuleId;

typedef enum {
    MODCAT_COLUMN,   /* own [X: ...] bracket per entry, dirs aggregate over
                       * direct children (LINES/CHARS/SIZE) or are the
                       * entry's own (PERMISSIONS/DATE/EXT/HASH)          */
    MODCAT_SUMMARY,  /* end-of-run block (TOTAL/FILES/DEBUG), not a column */
    MODCAT_DIFF,     /* DIFF -- marks entries + trailing note, its own thing */
    MODCAT_TOGGLE    /* TREE/HIDDEN -- changes what's walked/how it's laid
                       * out, not something that "shows" a value          */
} ModuleCat;

typedef struct {
    const char *name;
    ModuleId    id;
    ModuleCat   cat;
} ModuleDef;

extern const ModuleDef MODULE_TABLE[MOD_COUNT];

/* case-insensitive lookup by -o token name; NULL if unknown. */
const ModuleDef *module_lookup(const char *name);

#endif
