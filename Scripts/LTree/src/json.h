#ifndef LTREE_JSON_H
#define LTREE_JSON_H

#include "node.h"
#include "config.h"
#include "scan.h"
#include "exttable.h"
#include "util.h"
#include "debug.h"

/* Renders the full result (tree + totals + by-extension) as JSON into
 * `sb` (caller-owned, must already be sbuf_init'd). Used both for the
 * `-j` terminal output and for --save-output snapshots, so the two
 * never drift apart. `dbg` is only appended when non-NULL -- pass
 * NULL from save.c so runtime debug noise (timing, RSS, pid, ...)
 * never ends up baked into a saved snapshot that gets diffed later. */
void json_render(SBuf *sb, Node *root, const char *display_path,
                  const Totals *tot, const ExtTable *ext, const Config *cfg,
                  const DebugStats *dbg);

/* Convenience wrapper: renders and writes straight to stdout (the `-j`
 * code path). */
void print_json(Node *root, const char *display_path, const Totals *tot,
                 const ExtTable *ext, const Config *cfg, const DebugStats *dbg);

/* ===================== minimal generic JSON reader =====================
 * Just enough to parse our own JSON output back in (for -o DIFF). Not a
 * general-purpose validator -- assumes well-formed input, which is all
 * we ever hand it (files we wrote ourselves). */
typedef enum { JSON_NULL, JSON_BOOL, JSON_NUMBER, JSON_STRING, JSON_ARRAY, JSON_OBJECT } JType;

typedef struct JVal {
    JType type;
    bool   b;
    double num;
    char  *str;
    struct JVal **items;  /* array elements, or object values */
    char        **keys;   /* object keys (parallel to items), NULL for arrays */
    size_t        n;
} JVal;

JVal       *json_parse(const char *text);
void        json_free(JVal *v);
JVal       *json_obj_get(JVal *obj, const char *key); /* NULL if missing/not object */
const char *json_as_string(JVal *v);                  /* NULL if not a string */
double      json_as_number(JVal *v);
size_t      json_arr_len(JVal *v);
JVal       *json_arr_get(JVal *v, size_t i);

#endif
