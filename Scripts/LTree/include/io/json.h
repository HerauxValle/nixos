/* &desc: "Declares json_render/print_json (the JSON writer shared by -j and --save-output) plus a minimal recursive-descent JSON reader (json_parse and friends) just capable enough to round-trip ltree's own snapshot files for -o DIFF." */
#ifndef LTREE_JSON_H
#define LTREE_JSON_H

#include "core/node.h"
#include "core/config.h"
#include "scan/scan.h"
#include "scan/exttable.h"
#include "util/util.h"
#include "debug/debug.h"

/* Renders the full result (tree + totals + by-extension) as JSON into
 * `sb` (caller-owned, must already be sbuf_init'd). Used both for the
 * `-j` terminal output and for --save-output snapshots, so the two
 * never drift apart. `dbg` is only appended when non-NULL -- pass
 * NULL from save.c so runtime debug noise (timing, RSS, pid, ...)
 * never ends up baked into a saved snapshot that gets diffed later. */
void json_render(SBuf *sb, Node *root, const char *display_path,
                  const Totals *tot, const ExtTable *ext, const Config *cfg,
                  const DebugStats *dbg);

/* Whether module `id` is allowed to appear as a JSON key this run --
 * mirrors -o exactly (except TREE, always on -- see json.c). Exposed
 * (not just json.c-internal) so main.c can reuse the exact same rule to
 * decide whether a field is worth computing at all -- see
 * field_wanted() in main.c. */
bool json_key_allowed(const Config *cfg, ModuleId id);

/* Convenience wrapper: renders and writes straight to stdout (the `-j`
 * code path). */
void print_json(Node *root, const char *display_path, const Totals *tot,
                 const ExtTable *ext, const Config *cfg, const DebugStats *dbg);

/* -jL: the same fields as print_json's "tree", flattened to one compact
 * JSON object per line (NDJSON) instead of one nested structure --
 * streamable line-by-line (grep/jq -c/wc -l/...) without holding the
 * whole tree in memory to parse it. Shares json_key_allowed() with
 * json_render, so -o gates both writers identically. total/
 * by_extension/debug print as their own single "_type"-tagged lines
 * after every entry, gated by the same modules as print_json's. */
void print_json_lines(Node *root, const char *display_path, const Totals *tot,
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
