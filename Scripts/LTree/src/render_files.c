#define _GNU_SOURCE
#include "render_files.h"
#include "colors.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void print_files_summary(const ExtTable *ext, const Config *cfg) {
    if (ext->n == 0) return;
    ExtStat *sorted = (ExtStat *)malloc(sizeof(ExtStat) * ext->n);
    memcpy(sorted, ext->items, sizeof(ExtStat) * ext->n);
    qsort(sorted, ext->n, sizeof(ExtStat), extstat_cmp_desc_lines);

    size_t namew = 4; /* "TYPE" */
    for (size_t i = 0; i < ext->n; i++) {
        size_t w = strlen(sorted[i].ext);
        if (w > namew) namew = w;
    }

    printf("\n%sFILES:%s\n", COL(cfg, ANSI_TOTAL), RST(cfg));
    printf("  %-*s  %8s  %10s  %10s\n", (int)namew, "TYPE", "FILES", "LINES", "CHARS");
    for (size_t i = 0; i < ext->n; i++) {
        printf("  %s%-*s%s  %8ld  %10ld  %10ld\n",
               COL(cfg, ANSI_EXT), (int)namew, sorted[i].ext, RST(cfg),
               sorted[i].files, sorted[i].lines, sorted[i].chars);
    }
    free(sorted);
}
