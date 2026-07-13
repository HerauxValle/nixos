#ifndef LTREE_SAVE_H
#define LTREE_SAVE_H

#include "node.h"
#include "config.h"
#include "scan.h"
#include "exttable.h"

/* Writes the full JSON result to <ltree_snapshot_dir(cfg)>/dd-mm-yyyy_hh:mm:ss.json,
 * creating the .ltree directory if needed. Returns true on success;
 * prints a warning to stderr (non-fatal) on failure. */
bool save_output(Node *root, const char *display_path, const Totals *tot,
                  const ExtTable *ext, const Config *cfg);

#endif
