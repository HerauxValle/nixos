#define _GNU_SOURCE
#include "sort/sortmodes.h"
#include "core/node.h"
#include "scan/exttable.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

bool sort_parse(const char *arg, SortSpec *out) {
    memset(out, 0, sizeof(*out));
    out->base = SORT_ABC;
    out->set = true;
    bool base_set = false;

    char *copy = strdup(arg);
    char *tok = strtok(copy, ",");
    while (tok) {
        SortBaseMode base = SORT_ABC;
        bool is_base = true;

        if      (strcasecmp(tok, "abc") == 0)      base = SORT_ABC;
        else if (strcasecmp(tok, "birth") == 0)     base = SORT_BIRTH;
        else if (strcasecmp(tok, "modified") == 0)  base = SORT_MODIFIED;
        else if (strcasecmp(tok, "lines") == 0)     base = SORT_LINES;
        else if (strcasecmp(tok, "chars") == 0)     base = SORT_CHARS;
        else if (strcasecmp(tok, "types") == 0)     base = SORT_TYPES;
        else is_base = false;

        if (is_base) {
            if (base_set && base != out->base) {
                fprintf(stderr,
                        "error: --sort base modes are mutually exclusive "
                        "(got both another mode and '%s' in '--sort %s')\n", tok, arg);
                free(copy);
                return false;
            }
            out->base = base;
            base_set = true;
        } else if (strcasecmp(tok, "combined") == 0) {
            out->combined = true;
        } else if (strcasecmp(tok, "reversed") == 0) {
            out->reversed = true;
        } else {
            fprintf(stderr, "warning: unknown --sort mode '%s'\n", tok);
        }
        tok = strtok(NULL, ",");
    }
    free(copy);

    if (out->base == SORT_TYPES && out->combined) {
        fprintf(stderr,
                "warning: --sort types already groups by its own [ext] buckets; "
                "ignoring 'combined'\n");
        out->combined = false;
    }
    return true;
}

static SortSpec g_active_spec;

static int base_compare(SortBaseMode base, const Node *na, const Node *nb) {
    switch (base) {
        case SORT_BIRTH:    return (na->btime > nb->btime) - (na->btime < nb->btime);
        case SORT_MODIFIED: return (na->mtime > nb->mtime) - (na->mtime < nb->mtime);
        case SORT_LINES:    return (na->lines > nb->lines) - (na->lines < nb->lines);
        case SORT_CHARS:    return (na->chars > nb->chars) - (na->chars < nb->chars);
        case SORT_TYPES:    return strcasecmp(file_ext(na->name), file_ext(nb->name));
        case SORT_ABC:
        default:            return 0; /* falls straight to the name tie-break below */
    }
}

/* Single-threaded CLI tool, so a static "current sort spec" ahead of
 * qsort() is simpler and more portable than qsort_r() (whose argument
 * order differs between glibc and BSD/macOS libc). */
static int sort_cmp(const void *a, const void *b) {
    const Node *na = *(const Node * const *)a;
    const Node *nb = *(const Node * const *)b;
    int c = base_compare(g_active_spec.base, na, nb);
    if (c == 0) c = node_cmp(a, b); /* tie-break, and SORT_ABC's whole ordering */
    return g_active_spec.reversed ? -c : c;
}

void sort_nodes(Node **arr, size_t n, const SortSpec *spec) {
    g_active_spec = *spec;
    qsort(arr, n, sizeof(Node *), sort_cmp);
}
