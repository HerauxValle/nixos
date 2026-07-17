/* colors.h -- ANSI colour palette shared by render_tree.c,
 * render_files.c, and debug.c. All collapse to "" when cfg->no_colour
 * is set via the COL()/RST() macros, so print sites never branch on
 * no_colour themselves. */
#ifndef LTREE_COLORS_H
#define LTREE_COLORS_H

#include "core/config.h"

#define ANSI_RESET    "\x1b[0m"
#define ANSI_DIR      "\x1b[1;34m"   /* bold blue    -- directories        */
#define ANSI_FILE     "\x1b[0;37m"   /* light grey   -- regular files      */
#define ANSI_BRANCH   "\x1b[2;37m"   /* dim grey     -- tree branch glyphs */
#define ANSI_LINES    "\x1b[0;32m"   /* green        -- L: column          */
#define ANSI_CHARS    "\x1b[0;33m"   /* yellow       -- C: column          */
#define ANSI_TOTAL    "\x1b[1;36m"   /* bold cyan    -- TOTAL summary       */
#define ANSI_EXT      "\x1b[0;35m"   /* magenta      -- FILES extensions    */
#define ANSI_SYMLINK  "\x1b[1;35m"   /* bold magenta -- symlinks            */
#define ANSI_PERM     "\x1b[0;36m"   /* cyan         -- P: column           */
#define ANSI_SIZE     "\x1b[0;33m"   /* yellow       -- S: column           */
#define ANSI_DATE     "\x1b[2;37m"   /* dim grey     -- D: column           */
#define ANSI_HASH     "\x1b[0;35m"   /* magenta      -- H: column           */
#define ANSI_MODIFIED "\x1b[1;31m"   /* bold red     -- DIFF: modified name */
#define ANSI_NOTE     "\x1b[2;37m"   /* dim grey     -- trailing notes      */
#define ANSI_DEBUG    "\x1b[1;33m"   /* bold yellow  -- DEBUG: sub-dividers */

#define COL(cfg, code) ((cfg)->no_colour ? "" : (code))
#define RST(cfg)       ((cfg)->no_colour ? "" : ANSI_RESET)

#endif
