/* &desc: "Declares print_ls_view, the default (no -o TREE) non-recursive [Folders]/[Files] listing renderer -- packs into a real ls-style multi-column grid on a tty, --sort- and -o HIDDEN-aware." */
#ifndef LTREE_RENDER_LS_H
#define LTREE_RENDER_LS_H

#include "core/node.h"
#include "core/config.h"
#include "scan/scan.h"
#include "debug/debug.h"

/* prints the new default (no `-o TREE`) ls-style view: `root`'s direct
 * children only, non-recursive, grouped into a `[Folders]` block then
 * a `[Files]` block (each case-insensitive alphabetical, since that's
 * the order scan.c's build_tree() already sorts children into --
 * see docs/plan-ls-rework.md, Category 2). When stdout is a terminal
 * and no -o data column is active, each block packs into a real
 * `ls -C`-style multi-column grid instead of one entry per line
 * (piped output, or any active -o column, keeps the one-per-line
 * form). Same trailing TOTAL/FILES/DEBUG/DIFF-note tail as the
 * streaming -o TREE view (render_tree.h), same order. */
void print_ls_view(Node *root, const char *display_path, const Config *cfg,
                    const Totals *tot, bool diff_available, const DebugStats *dbg);

#endif
