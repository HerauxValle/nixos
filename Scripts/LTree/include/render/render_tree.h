/* &desc: "Declares print_tree_view (the default, buffered, whole-tree-aligned -o TREE renderer) and the tree_live_* streaming hooks (--live, fixed-width columns instead of measured) that print top-down as scan.c's build_tree walks." */
#ifndef LTREE_RENDER_TREE_H
#define LTREE_RENDER_TREE_H

#include "core/node.h"
#include "core/config.h"
#include "scan/scan.h"
#include "debug/debug.h"

/* The default -o TREE view: buffered, whole-tree-aligned. Flattens
 * the already-complete Node tree into one LineBuf, measures every
 * active column's width across the WHOLE tree, then prints -- same
 * convention as the ls-mode view (render_ls.c). Only usable once
 * build_tree() has fully returned; nothing streams. */
void print_tree_view(Node *root, const char *display_path, const Config *cfg,
                      const Totals *tot, bool diff_available, const DebugStats *dbg);

/* --live: streams -o TREE output top-down as scan.c's build_tree()
 * walks, instead of waiting for the whole tree. Since nothing beyond
 * the directory currently being printed is known yet, whole-tree
 * column alignment is impossible -- this uses FIXED-width columns
 * instead (see columns.h's columns_measure_fixed()), so output still
 * lines up at a predictable position rather than a jagged,
 * per-directory one. Call order: tree_live_start() once (prints the
 * root header line), then wire tree_live_on_dir_measure/
 * tree_live_on_entry_ready/tree_live_on_dir_done as build_tree()'s
 * three hooks (see scan/scan.h for exactly when each fires) for the
 * walk, then tree_live_end() once the walk finishes to free internal
 * state. TOTAL:/FILES:/DEBUG:/the DIFF note are NOT part of this --
 * print those separately afterward via columns.c's
 * print_summary_tail(), same as the buffered view. */
void tree_live_start(const char *display_path, const Config *cfg);
void tree_live_on_dir_measure(Node *dir, int depth, const Config *cfg, void *ctx);
void tree_live_on_entry_ready(Node *node, size_t index, bool is_last, int depth,
                               const Config *cfg, void *ctx);
void tree_live_on_dir_done(int depth, const Config *cfg, void *ctx);
void tree_live_end(void);

#endif
