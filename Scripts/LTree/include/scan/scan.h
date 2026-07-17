/* &desc: "Declares build_tree (the one recursive filesystem walk, with three optional streaming hooks -- measure/entry/done -- that let -o TREE print top-down as it walks), fetch_btime (creation time via statx for --sort birth), and the Totals struct." */
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

/* Streaming support (what lets -o TREE print top-down as the walk
 * happens instead of buffering the whole tree first -- see
 * render/render_tree.h for the implementation main.c wires up here,
 * and docs/plan-ls-rework.md, Category 7, for why this needs two
 * hooks instead of one). Firing order for a given directory `dir` at
 * depth `depth`, once its children are known and attached:
 *
 *   1. on_dir_measure(dir, depth, ...)  -- once, before any of dir's
 *      children print, so a renderer can size columns across all of
 *      them up front (needed for per-directory-block alignment).
 *   2. on_entry_ready(child, index, is_last, depth+1, ...) -- once
 *      per child, in sorted order, immediately before build_tree()
 *      decides whether to recurse into it. If it's a directory that
 *      recurses, ITS on_dir_measure/on_entry_ready calls (at
 *      depth+2) happen in between this call and the next sibling's --
 *      interleaved with the walk, not batched, so a subtree prints
 *      right after its own directory's line instead of after all its
 *      siblings.
 *   3. on_dir_done(depth+1, ...) -- once, after every child (and
 *      everything recursed into) has been processed, so a renderer
 *      can free whatever per-directory state it built in step 1.
 */
typedef void (*DirMeasureFn)(Node *dir, int depth, const Config *cfg, void *ctx);
typedef void (*EntryReadyFn)(Node *node, size_t index, bool is_last, int depth,
                              const Config *cfg, void *ctx);
typedef void (*DirDoneFn)(int depth, const Config *cfg, void *ctx);

/* Recursively walks `fullpath`, populating `parent`'s children.
 * `gt` may be NULL if --gitignore wasn't requested. The three hooks
 * may all be NULL (no streaming wanted, e.g. ls-mode/-j); `ctx` is
 * passed through to whichever of them fire, untouched. */
void build_tree(Node *parent, const char *fullpath, const char *relbase,
                 int depth, const Config *cfg, const GitTable *gt,
                 Totals *totals, ExtTable *ext,
                 DirMeasureFn on_dir_measure, EntryReadyFn on_entry_ready,
                 DirDoneFn on_dir_done, void *ctx);

#endif
