/* scan.h -- the one filesystem walk. Fills in every stat/line/char/
 * hash field on the Node tree as it goes, so the expensive part
 * (stat + mmap + byte scanning + hashing) happens exactly once per
 * file no matter how many -o sections were requested. */
#ifndef LTREE_SCAN_H
#define LTREE_SCAN_H

#include "node.h"
#include "config.h"
#include "exttable.h"
#include "gitignore.h"

typedef struct {
    long dirs;
    long files;
    long lines;
    long chars;
} Totals;

void parse_exclude_list(const char *arg, char ***out, size_t *out_n);

/* Recursively walks `fullpath`, populating `parent`'s children.
 * `gt` may be NULL if --gitignore wasn't requested. */
void build_tree(Node *parent, const char *fullpath, const char *relbase,
                 int depth, const Config *cfg, const GitTable *gt,
                 Totals *totals, ExtTable *ext);

#endif
