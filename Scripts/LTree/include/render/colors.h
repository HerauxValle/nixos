/* &desc: "Defines the shared ANSI colour palette and the COL()/RST() macros that collapse to empty strings under --no-colour, so no print site has to branch on that flag itself." */
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
#define ANSI_DESC     "\x1b[1;37m"   /* bold white   -- DESC: column        */
#define ANSI_MODIFIED "\x1b[1;31m"   /* bold red     -- DIFF: modified name */
#define ANSI_NOTE     "\x1b[2;37m"   /* dim grey     -- trailing notes      */
#define ANSI_DEBUG    "\x1b[1;33m"   /* bold yellow  -- DEBUG: sub-dividers */

/* ls-mode file-name colouring by kind (render_ls.c's file_name_color())
 * -- deliberately the "bright" 9x foreground range, not the standard
 * 3x/1;3x range every other colour above uses, so a richly-coloured
 * file listing never collides with (or gets mistaken for) an existing
 * semantic colour like MODIFIED/SYMLINK/DEBUG above. Tree mode doesn't
 * read these yet (see PrintLine.namecolor in columns.h). CODE/MARKUP
 * reuse IMAGE/MEDIA's hues at bold weight instead of claiming a 7th/8th
 * fresh hue -- the bright range only has 6 (91-96; 90/97 are grey/near-
 * white, too easily mistaken for FILE/DESC's already-similar shades) --
 * bold vs plain is enough separation since a file's extension is right
 * there next to it either way. */
#define ANSI_EXEC     "\x1b[0;92m"   /* bright green        -- executable file */
#define ANSI_ARCHIVE  "\x1b[0;91m"   /* bright red          -- tar/zip/gz/...  */
#define ANSI_IMAGE    "\x1b[0;95m"   /* bright magenta      -- png/jpg/svg/... */
#define ANSI_MEDIA    "\x1b[0;96m"   /* bright cyan         -- mp3/mp4/mkv/... */
#define ANSI_DOC      "\x1b[0;93m"   /* bright yellow       -- md/txt/pdf/...  */
#define ANSI_CONFIG   "\x1b[0;94m"   /* bright blue         -- json/yaml/nix.. */
#define ANSI_CODE     "\x1b[1;96m"   /* bold bright cyan    -- c/py/rs/js/...  */
#define ANSI_MARKUP   "\x1b[1;95m"   /* bold bright magenta -- html/css/xml/.. */

/* ls-mode folder-name colouring by common role (render_ls.c's
 * dir_name_color()) -- matched case-insensitively against the whole
 * folder name (src/Src/SRC all the same), not by any extension.
 * Reuses the exact same file-kind hues where the mental mapping is
 * obvious (docs/ -> ANSI_DOC's yellow) since folders and files never
 * share a row (ls mode always splits [Folders] from [Files]), so the
 * hue reuse can't actually be confused for the wrong kind. BUILD uses
 * the existing dim BRANCH/NOTE grey -- generated output deliberately
 * recedes rather than competing for attention with real source. */
#define ANSI_DIR_SRC    ANSI_EXEC     /* src/lib/cmd/cli/pkg/...        */
#define ANSI_DIR_DOCS   ANSI_DOC      /* docs/wiki/man/...              */
#define ANSI_DIR_TEST   ANSI_IMAGE    /* test/tests/spec/e2e/...        */
#define ANSI_DIR_BUILD  "\x1b[2;37m"  /* dim grey -- build/dist/target  */
#define ANSI_DIR_VENDOR ANSI_ARCHIVE  /* node_modules/vendor/deps/...   */
#define ANSI_DIR_ASSETS ANSI_MEDIA    /* assets/static/public/...       */

#define COL(cfg, code) ((cfg)->no_colour ? "" : (code))
#define RST(cfg)       ((cfg)->no_colour ? "" : ANSI_RESET)

#endif
