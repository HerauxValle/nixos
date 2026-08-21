/* &desc: "Declares the GitTable type and gitignore_load/gitignore_is_excluded, --gitignore's single-root-.gitignore matcher (a documented subset of real gitignore semantics)." */
/* gitignore.h -- reads a single .gitignore at the scan root and
 * matches against it. This is a *subset* of real gitignore semantics
 * (documented in docs/usage.md), not a full implementation:
 *   - comments ('#') and blank lines are skipped
 *   - trailing '/' means "directories only"
 *   - leading '/' anchors the pattern to the scan root; otherwise it
 *     matches the basename at any depth (same convention as --exclude)
 *   - a leading '!' re-includes a path a later/earlier pattern excluded
 *     (patterns are applied in file order, last match wins, exactly
 *     like real gitignore)
 *   - nested .gitignore files (one per subdirectory) are NOT read;
 *     only the scan root's .gitignore applies
 * Composable with --exclude: both lists are consulted together.
 */
#ifndef LTREE_GITIGNORE_H
#define LTREE_GITIGNORE_H

#include <stdbool.h>
#include <stddef.h>

typedef struct {
    char *pattern;
    bool  negate;
    bool  dir_only;
    bool  anchored;
} GitPattern;

typedef struct {
    GitPattern *items;
    size_t      n, cap;
} GitTable;

/* Reads "<root_dir>/.gitignore" if it exists. Silent no-op (gt->n == 0)
 * if the file is absent -- never an error. */
void gitignore_load(const char *root_dir, GitTable *gt);

/* last-match-wins evaluation over all patterns, per real gitignore
 * semantics. `relpath` is relative to the scan root. */
bool gitignore_is_excluded(const GitTable *gt, const char *basename,
                            const char *relpath, bool is_dir);

void gitignore_free(GitTable *gt);

#endif
