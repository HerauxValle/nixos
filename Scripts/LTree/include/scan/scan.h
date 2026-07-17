/* scan.h -- the one filesystem walk. Fills in every stat/line/char/
 * hash field on the Node tree as it goes, so the expensive part
 * (stat + mmap + byte scanning + hashing) happens exactly once per
 * file no matter how many -o sections were requested. */
#ifndef LTREE_SCAN_H
#define LTREE_SCAN_H

#include "core/node.h"
#include "core/config.h"
#include "scan/exttable.h"
#include "scan/gitignore.h"

typedef struct {
    long dirs;
    long files;
    long lines;
    long chars;
} Totals;

void parse_exclude_list(const char *arg, char ***out, size_t *out_n);

/* Birth time via statx()'s STATX_BTIME, falling back to
 * `mtime_fallback` when the filesystem/kernel doesn't report one.
 * Exposed so main.c can fill in the root Node's btime the same way
 * build_tree() fills in every other node's. */
time_t fetch_btime(const char *path, time_t mtime_fallback);

/* --live support: fired once a directory's own direct children are
 * fully known, before build_tree() recurses into any of them --
 * `dir` is that directory's Node (already attached to its own parent,
 * `dir->children` complete), `relpath` its path relative to the scan
 * root. See render/render_live.h for the implementation main.c wires
 * up here, and docs/plan-ls-rework.md, Category 7, for why this fires
 * top-down instead of depth-first-last. */
typedef void (*DirReadyFn)(Node *dir, const char *relpath, const Config *cfg, void *ctx);

/* Recursively walks `fullpath`, populating `parent`'s children.
 * `gt` may be NULL if --gitignore wasn't requested. `on_dir_ready`
 * may be NULL (no --live callback wanted); `live_ctx` is passed
 * through to it untouched. */
void build_tree(Node *parent, const char *fullpath, const char *relbase,
                 int depth, const Config *cfg, const GitTable *gt,
                 Totals *totals, ExtTable *ext,
                 DirReadyFn on_dir_ready, void *live_ctx);

#endif
