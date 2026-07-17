/* &desc: "Implements node_new/node_add_child/node_free and node_cmp, the case-insensitive alphabetical qsort comparator used as the default ordering throughout." */
#define _GNU_SOURCE
#include "core/node.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

Node *node_new(const char *name, bool is_dir) {
    Node *n = (Node *)calloc(1, sizeof(Node));
    if (!n) { perror("calloc"); exit(1); }
    n->name = strdup(name);
    n->is_dir = is_dir;
    return n;
}

void node_add_child(Node *parent, Node *child) {
    if (parent->nchildren == parent->children_cap) {
        parent->children_cap = parent->children_cap ? parent->children_cap * 2 : 8;
        parent->children = (Node **)realloc(parent->children,
                                             sizeof(Node *) * parent->children_cap);
        if (!parent->children) { perror("realloc"); exit(1); }
    }
    parent->children[parent->nchildren++] = child;
}

void node_free(Node *n) {
    if (!n) return;
    for (size_t i = 0; i < n->nchildren; i++) node_free(n->children[i]);
    free(n->children);
    free(n->name);
    free(n->desc);
    free(n);
}

int node_cmp(const void *a, const void *b) {
    const Node *na = *(const Node **)a;
    const Node *nb = *(const Node **)b;
    return strcasecmp(na->name, nb->name);
}
