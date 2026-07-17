/* &desc: "Implements print_files_summary, the FILES: by-extension table using the same [X: value] bracket-and-column-alignment convention as per-entry columns." */
#define _GNU_SOURCE
#include "render/render_files.h"
#include "render/colors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Same [X: value] bracket convention as every per-entry column (see
 * docs/plan-ls-rework.md, Category 10) -- each of the four columns
 * (TYPE/FILES/LINES/CHARS) gets its own bracket, padded to its own
 * widest value across every extension row, fixed 3-space gap between
 * columns, same as render/columns.c's per-entry rendering. */
void print_files_summary(const ExtTable *ext, const Config *cfg) {
    if (ext->n == 0) return;
    ExtStat *sorted = (ExtStat *)malloc(sizeof(ExtStat) * ext->n);
    memcpy(sorted, ext->items, sizeof(ExtStat) * ext->n);
    qsort(sorted, ext->n, sizeof(ExtStat), extstat_cmp_desc_lines);

    char **type_txt = (char **)malloc(sizeof(char *) * ext->n);
    char **files_txt = (char **)malloc(sizeof(char *) * ext->n);
    char **lines_txt = (char **)malloc(sizeof(char *) * ext->n);
    char **chars_txt = (char **)malloc(sizeof(char *) * ext->n);
    size_t type_w = 0, files_w = 0, lines_w = 0, chars_w = 0;

    for (size_t i = 0; i < ext->n; i++) {
        char buf[64];
        snprintf(buf, sizeof(buf), "[TYPE: %s]", sorted[i].ext);
        type_txt[i] = strdup(buf);
        if (strlen(buf) > type_w) type_w = strlen(buf);

        snprintf(buf, sizeof(buf), "[FILES: %ld]", sorted[i].files);
        files_txt[i] = strdup(buf);
        if (strlen(buf) > files_w) files_w = strlen(buf);

        snprintf(buf, sizeof(buf), "[LINES: %ld]", sorted[i].lines);
        lines_txt[i] = strdup(buf);
        if (strlen(buf) > lines_w) lines_w = strlen(buf);

        snprintf(buf, sizeof(buf), "[CHARS: %ld]", sorted[i].chars);
        chars_txt[i] = strdup(buf);
        if (strlen(buf) > chars_w) chars_w = strlen(buf);
    }

    printf("\n%sFILES:%s\n", COL(cfg, ANSI_TOTAL), RST(cfg));
    for (size_t i = 0; i < ext->n; i++) {
        printf("  %s%-*s%s   %-*s   %-*s   %-*s\n",
               COL(cfg, ANSI_EXT), (int)type_w, type_txt[i], RST(cfg),
               (int)files_w, files_txt[i],
               (int)lines_w, lines_txt[i],
               (int)chars_w, chars_txt[i]);
        free(type_txt[i]); free(files_txt[i]); free(lines_txt[i]); free(chars_txt[i]);
    }
    free(type_txt); free(files_txt); free(lines_txt); free(chars_txt);
    free(sorted);
}
