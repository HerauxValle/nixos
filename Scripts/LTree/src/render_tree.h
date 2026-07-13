#ifndef LTREE_RENDER_TREE_H
#define LTREE_RENDER_TREE_H

#include "node.h"
#include "config.h"
#include "scan.h"

/* prints the aligned tree view + (if cfg->o_total) the TOTAL: summary.
 * `diff_available` controls the trailing "no previous snapshot" note
 * when -o DIFF was requested but nothing was found to compare against. */
void print_tree_view(Node *root, const char *display_path, const Config *cfg,
                      const Totals *tot, bool diff_available);

#endif
