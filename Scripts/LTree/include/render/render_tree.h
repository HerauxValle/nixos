/* &desc: "Declares the -o TREE streaming hooks (tree_stream_start/on_dir_measure/on_entry_ready/on_dir_done/end) that print the connector-tree top-down as scan.c's build_tree walks, instead of buffering the whole tree first." */
#ifndef LTREE_RENDER_TREE_H
#define LTREE_RENDER_TREE_H

#include "core/node.h"
#include "core/config.h"
#include "scan/scan.h"

/* -o TREE always streams -- there's no buffered/non-streaming mode to
 * opt into, the same way plain `tree`/`find` don't need a flag to
 * print as they walk (see docs/plan-ls-rework.md, Category 7). Call
 * order: tree_stream_start() once (prints the root header line), then
 * wire tree_stream_on_dir_measure/tree_stream_on_entry_ready/
 * tree_stream_on_dir_done as build_tree()'s three hooks (see
 * scan/scan.h for exactly when each fires) for the walk, then
 * tree_stream_end() once the walk finishes to free internal state.
 * TOTAL:/FILES:/DEBUG:/the DIFF note are NOT part of this -- print
 * those separately afterward via columns.c's print_summary_tail(),
 * same as ls-mode. */
void tree_stream_start(const char *display_path, const Config *cfg);
void tree_stream_on_dir_measure(Node *dir, int depth, const Config *cfg, void *ctx);
void tree_stream_on_entry_ready(Node *node, size_t index, bool is_last, int depth,
                                 const Config *cfg, void *ctx);
void tree_stream_on_dir_done(int depth, const Config *cfg, void *ctx);
void tree_stream_end(void);

#endif
