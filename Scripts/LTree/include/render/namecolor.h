/* &desc: "Declares file_name_color()/dir_name_color(), the kind-by-extension and role-by-folder-name colour lookups shared by render_ls.c and render_tree.c." */
#ifndef LTREE_NAMECOLOR_H
#define LTREE_NAMECOLOR_H

#include <stdbool.h>
#include <sys/types.h>
#include "core/config.h"

/* Picks a kind-specific colour for a file name (not a directory), or
 * NULL for "no kind-specific colour, caller falls back to ANSI_FILE"
 * -- --no-colour, no extension, or an extension that doesn't match any
 * category. Must run against the file's ORIGINAL name (before any
 * EXT-stripping a caller might do for display, which would lose the
 * very extension this looks up). The executable bit wins over
 * extension when both apply, same precedence real `ls` gives a script
 * marked +x regardless of what it's named. Case-insensitive extension
 * match. See render/colors.h for the palette these return. */
const char *file_name_color(const Config *cfg, const char *name, mode_t mode);

/* Same idea for directories, matched by whole name (case-insensitively
 * -- src/Src/SRC all the same) against common mainstream folder-role
 * names instead of any extension. NULL for "no role match, caller
 * falls back to plain ANSI_DIR" -- most folder names (a project's own
 * domain-specific ones) won't match anything here, which is expected. */
const char *dir_name_color(const Config *cfg, const char *name);

#endif
