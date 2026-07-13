#define _GNU_SOURCE
#include "exttable.h"
#include <stdlib.h>
#include <string.h>

void exttable_init(ExtTable *t) {
    t->cap = 16; t->n = 0;
    t->items = (ExtStat *)malloc(sizeof(ExtStat) * t->cap);
}

void exttable_add(ExtTable *t, const char *ext, long lines, long chars) {
    for (size_t i = 0; i < t->n; i++) {
        if (strcmp(t->items[i].ext, ext) == 0) {
            t->items[i].files++;
            t->items[i].lines += lines;
            t->items[i].chars += chars;
            return;
        }
    }
    if (t->n == t->cap) {
        t->cap *= 2;
        t->items = (ExtStat *)realloc(t->items, sizeof(ExtStat) * t->cap);
    }
    t->items[t->n].ext = strdup(ext);
    t->items[t->n].files = 1;
    t->items[t->n].lines = lines;
    t->items[t->n].chars = chars;
    t->n++;
}

void exttable_free(ExtTable *t) {
    for (size_t i = 0; i < t->n; i++) free(t->items[i].ext);
    free(t->items);
}

int extstat_cmp_desc_lines(const void *a, const void *b) {
    const ExtStat *ea = (const ExtStat *)a, *eb = (const ExtStat *)b;
    if (eb->lines != ea->lines) return (eb->lines > ea->lines) ? 1 : -1;
    return strcmp(ea->ext, eb->ext);
}

const char *file_ext(const char *name) {
    const char *dot = strrchr(name, '.');
    if (!dot || dot == name) return "(no ext)";
    return dot + 1;
}

char *strip_ext_for_display(const char *name) {
    const char *dot = strrchr(name, '.');
    if (!dot || dot == name) return strdup(name);
    size_t n = (size_t)(dot - name);
    char *out = (char *)malloc(n + 1);
    memcpy(out, name, n);
    out[n] = '\0';
    return out;
}
