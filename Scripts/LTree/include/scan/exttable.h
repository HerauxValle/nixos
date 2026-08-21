/* &desc: "Declares the per-extension files/lines/chars accumulator (ExtTable) shared by the FILES: summary, the JSON by_extension block, and --sort types' bucketing, plus file_ext()/strip_ext_for_display()." */
#ifndef LTREE_EXTTABLE_H
#define LTREE_EXTTABLE_H

#include <stddef.h>

typedef struct {
    char *ext;      /* "(no ext)" for extensionless files */
    long  files;
    long  lines;
    long  chars;
} ExtStat;

typedef struct {
    ExtStat *items;
    size_t   n, cap;
} ExtTable;

void exttable_init(ExtTable *t);
void exttable_add(ExtTable *t, const char *ext, long lines, long chars);
void exttable_free(ExtTable *t);
int  extstat_cmp_desc_lines(const void *a, const void *b);

/* returns "(no ext)" for names with no '.' (or a leading-dot dotfile) */
const char *file_ext(const char *name);

/* malloc'd copy of `name` with the extension stripped (e.g. "report.md"
 * -> "report"). Leading-dot dotfiles ("*.gitignore") and extensionless
 * names are returned unchanged. Used for the default -o EXT-hidden
 * display; the real name/extension are still tracked separately for
 * FILES:/JSON, which are unaffected by this. Caller frees. */
char *strip_ext_for_display(const char *name);

#endif
