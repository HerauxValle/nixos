#ifndef LTREE_SAVE_H
#define LTREE_SAVE_H

#include "core/node.h"
#include "core/config.h"
#include "scan/scan.h"
#include "scan/exttable.h"

/* Writes the full JSON result to <ltree_snapshot_dir(cfg)>/dd-mm-yyyy_hh:mm:ss.json,
 * creating the .ltree directory if needed. Returns true on success;
 * prints a warning to stderr (non-fatal) on failure. */
bool save_output(Node *root, const char *display_path, const Totals *tot,
                  const ExtTable *ext, const Config *cfg);

#endif
