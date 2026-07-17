#ifndef LTREE_RENDER_LIVE_H
#define LTREE_RENDER_LIVE_H

#include "core/node.h"
#include "core/config.h"

/* --live's DirReadyFn (see scan/scan.h): prints `dir`'s direct
 * children (a flat listing, no [Folders]/[Files] split -- live mode
 * is its own simpler streaming format, not a live-updated version of
 * the tree/ls views) as soon as they're known, column-aligned to just
 * this one directory's own entries, then flushes stdout. `ctx` is
 * unused (kept to match DirReadyFn's signature). */
void render_live_dir_block(Node *dir, const char *relpath, const Config *cfg, void *ctx);

#endif
