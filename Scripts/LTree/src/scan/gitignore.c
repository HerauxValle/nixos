#define _GNU_SOURCE
#include "scan/gitignore.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fnmatch.h>
#include <limits.h>

static void gt_push(GitTable *gt, const char *pat, bool negate, bool dir_only, bool anchored) {
    if (gt->n == gt->cap) {
        gt->cap = gt->cap ? gt->cap * 2 : 16;
        gt->items = (GitPattern *)realloc(gt->items, sizeof(GitPattern) * gt->cap);
    }
    gt->items[gt->n].pattern  = strdup(pat);
    gt->items[gt->n].negate   = negate;
    gt->items[gt->n].dir_only = dir_only;
    gt->items[gt->n].anchored = anchored;
    gt->n++;
}

void gitignore_load(const char *root_dir, GitTable *gt) {
    gt->items = NULL; gt->n = 0; gt->cap = 0;

    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/.gitignore", root_dir);
    FILE *f = fopen(path, "r");
    if (!f) return; /* no .gitignore -- not an error */

    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        /* strip trailing newline/CR */
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r')) line[--len] = '\0';

        char *p = line;
        while (*p == ' ' || *p == '\t') p++;   /* leading whitespace */
        if (*p == '\0' || *p == '#') continue; /* blank / comment */

        bool negate = false;
        if (*p == '!') { negate = true; p++; }

        bool anchored = false;
        if (*p == '/') { anchored = true; p++; }

        size_t plen = strlen(p);
        bool dir_only = false;
        if (plen > 0 && p[plen - 1] == '/') { dir_only = true; p[plen - 1] = '\0'; }

        if (*p == '\0') continue;
        gt_push(gt, p, negate, dir_only, anchored);
    }
    fclose(f);
}

bool gitignore_is_excluded(const GitTable *gt, const char *basename,
                            const char *relpath, bool is_dir) {
    bool excluded = false;
    for (size_t i = 0; i < gt->n; i++) {
        const GitPattern *g = &gt->items[i];
        if (g->dir_only && !is_dir) continue;

        bool hit = g->anchored ? (fnmatch(g->pattern, relpath, 0) == 0)
                                : (fnmatch(g->pattern, basename, 0) == 0 ||
                                   fnmatch(g->pattern, relpath, 0) == 0);
        if (hit) excluded = !g->negate;
    }
    return excluded;
}

void gitignore_free(GitTable *gt) {
    for (size_t i = 0; i < gt->n; i++) free(gt->items[i].pattern);
    free(gt->items);
    gt->items = NULL; gt->n = gt->cap = 0;
}
