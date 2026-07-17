#ifndef LTREE_RENDER_TREE_H
#define LTREE_RENDER_TREE_H

#include "core/node.h"
#include "core/config.h"
#include "scan/scan.h"
#include "debug/debug.h"

/* prints the aligned tree view + (if cfg->modules[MOD_TOTAL]) the
 * TOTAL: summary, + (if cfg->modules[MOD_DEBUG] and dbg != NULL) the
 * DEBUG: summary right after it. `diff_available` controls the
 * trailing "no previous snapshot" note when -o DIFF was requested but
 * nothing was found to compare against -- that note is printed last,
 * after DEBUG. */
void print_tree_view(Node *root, const char *display_path, const Config *cfg,
                      const Totals *tot, bool diff_available, const DebugStats *dbg);

#endif
