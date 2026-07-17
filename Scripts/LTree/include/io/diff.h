/* &desc: "Declares diff_apply/find_latest_snapshot/diff_peek_algo, the -o DIFF API that loads the newest .ltree JSON snapshot and marks which Node entries changed since it was taken." */
/* diff.h -- -o DIFF support: find the newest .ltree JSON snapshot,
 * load it, and mark Nodes in the freshly-scanned tree as `modified`
 * when they differ from the snapshot. Per the design decision in
 * plan.md, comparison always uses whichever hash algorithm produced
 * the snapshot (stored in its "hash_algo" field), regardless of
 * --cryptographic on the current run -- diffing only works when both
 * sides are hashed the same way. */
#ifndef LTREE_DIFF_H
#define LTREE_DIFF_H

#include <stdbool.h>
#include "core/node.h"
#include "core/config.h"
#include "hash/hash.h"

/* Directory that --save-output / -o DIFF treat as the snapshot store
 * for this run: `<save_output_dir or scan root>/.ltree`. Result is
 * malloc'd, caller frees. */
char *ltree_snapshot_dir(const Config *cfg);

/* Finds the lexicographically/chronologically newest *.json in `dir`.
 * Returns a malloc'd path, or NULL if the directory doesn't exist or
 * has no snapshots. Filenames are parsed as timestamps rather than
 * string-sorted, since dd-mm-yyyy does not sort chronologically as
 * text. */
char *find_latest_snapshot(const char *dir);

/* Reads just the "hash_algo" field out of a snapshot, without doing
 * any tree comparison work. Used by main.c BEFORE scanning, since the
 * scan itself needs to know which algorithm to hash with in order to
 * produce comparable digests. Returns HASH_ALGO_NONE if unreadable. */
HashAlgo diff_peek_algo(const char *snapshot_path);

/* Loads `snapshot_path`, determines which hash algorithm it was
 * generated with (from its "hash_algo" field), and walks `root`
 * (freshly scanned, using that same algorithm -- caller is
 * responsible for having scanned with cfg->hash_algo already forced
 * to match, see main.c) marking `modified` on every node whose hash
 * differs from the snapshot's corresponding entry by relative path.
 * Returns the algorithm the snapshot was made with, or HASH_ALGO_NONE
 * if the snapshot couldn't be read. */
HashAlgo diff_apply(const char *snapshot_path, Node *root);

#endif
