#define _GNU_SOURCE
#include "diff.h"
#include "json.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <limits.h>

char *ltree_snapshot_dir(const Config *cfg) {
    const char *base = cfg->save_output_dir ? cfg->save_output_dir : cfg->path;
    size_t len = strlen(base) + strlen("/.ltree") + 1;
    char *out = (char *)malloc(len);
    snprintf(out, len, "%s/.ltree", base);
    return out;
}

/* dd-mm-yyyy_hh:mm:ss.json -- parsed with mktime() rather than string
 * sorted, since day-month-year does not sort chronologically as text. */
static bool parse_snapshot_filename_time(const char *fname, time_t *out) {
    struct tm tmv;
    memset(&tmv, 0, sizeof(tmv));
    int d, mo, y, h, mi, s;
    if (sscanf(fname, "%2d-%2d-%4d_%2d:%2d:%2d.json", &d, &mo, &y, &h, &mi, &s) != 6)
        return false;
    tmv.tm_mday = d; tmv.tm_mon = mo - 1; tmv.tm_year = y - 1900;
    tmv.tm_hour = h; tmv.tm_min = mi; tmv.tm_sec = s;
    tmv.tm_isdst = -1;
    time_t t = mktime(&tmv);
    if (t == (time_t)-1) return false;
    *out = t;
    return true;
}

char *find_latest_snapshot(const char *dir) {
    DIR *d = opendir(dir);
    if (!d) return NULL;

    struct dirent *de;
    time_t best_time = 0;
    char best_name[PATH_MAX] = {0};
    bool found = false;

    while ((de = readdir(d)) != NULL) {
        size_t len = strlen(de->d_name);
        if (len < 6 || strcmp(de->d_name + len - 5, ".json") != 0) continue;
        time_t t;
        if (!parse_snapshot_filename_time(de->d_name, &t)) continue;
        if (!found || t > best_time) {
            found = true;
            best_time = t;
            snprintf(best_name, sizeof(best_name), "%s", de->d_name);
        }
    }
    closedir(d);
    if (!found) return NULL;

    size_t outlen = strlen(dir) + 1 + strlen(best_name) + 1;
    char *out = (char *)malloc(outlen);
    snprintf(out, outlen, "%s/%s", dir, best_name);
    return out;
}

/* ===================== snapshot flattening =============================
 * Turns the parsed JVal tree back into a flat, sorted-by-path table so
 * comparing against the freshly-scanned Node tree is a bsearch instead
 * of a parallel tree walk (the two trees can differ in shape when
 * files were added/removed, so a flat lookup is simpler and correct).
 * ===================================================================== */
typedef struct {
    char    *path;
    bool     is_dir;
    uint8_t  hash[HASH_MAX_BYTES];
    uint8_t  hash_len;
    int64_t  size;
    time_t   mtime;
} SnapEntry;

typedef struct {
    SnapEntry *items;
    size_t     n, cap;
} SnapTable;

static void snap_push(SnapTable *t, const char *path, bool is_dir,
                       const uint8_t *hash, uint8_t hlen, int64_t size, time_t mtime) {
    if (t->n == t->cap) {
        t->cap = t->cap ? t->cap * 2 : 64;
        t->items = (SnapEntry *)realloc(t->items, sizeof(SnapEntry) * t->cap);
    }
    SnapEntry *e = &t->items[t->n++];
    e->path = strdup(path);
    e->is_dir = is_dir;
    memcpy(e->hash, hash, HASH_MAX_BYTES);
    e->hash_len = hlen;
    e->size = size;
    e->mtime = mtime;
}

static void flatten_jval(JVal *node, const char *prefix, SnapTable *t) {
    if (!node) return;
    const char *name = json_as_string(json_obj_get(node, "name"));
    const char *type = json_as_string(json_obj_get(node, "type"));
    bool is_dir = type && strcmp(type, "dir") == 0;

    char path[PATH_MAX];
    if (prefix[0] == '\0') snprintf(path, sizeof(path), "%s", name ? name : "");
    else snprintf(path, sizeof(path), "%s/%s", prefix, name ? name : "");

    uint8_t hash[HASH_MAX_BYTES] = {0};
    uint8_t hlen = 0;
    const char *hex = json_as_string(json_obj_get(node, "hash"));
    if (hex) hlen = (uint8_t)hex_decode(hex, hash, HASH_MAX_BYTES);

    int64_t size = (int64_t)json_as_number(json_obj_get(node, "size"));
    time_t mtime = (time_t)json_as_number(json_obj_get(node, "mtime"));

    snap_push(t, path, is_dir, hash, hlen, size, mtime);

    if (is_dir) {
        JVal *children = json_obj_get(node, "children");
        size_t n = json_arr_len(children);
        for (size_t i = 0; i < n; i++) flatten_jval(json_arr_get(children, i), path, t);
    }
}

static void flatten_snapshot_root(JVal *tree_root, SnapTable *t) {
    if (!tree_root) return;
    JVal *children = json_obj_get(tree_root, "children");
    size_t n = json_arr_len(children);
    for (size_t i = 0; i < n; i++) flatten_jval(json_arr_get(children, i), "", t);
}

static int snapentry_cmp(const void *a, const void *b) {
    const SnapEntry *ea = (const SnapEntry *)a, *eb = (const SnapEntry *)b;
    return strcmp(ea->path, eb->path);
}

/* ===================== comparison against the live tree ================= */
static void mark_diff_recursive(Node *n, const char *prefix, SnapTable *t) {
    for (size_t i = 0; i < n->nchildren; i++) {
        Node *c = n->children[i];
        char path[PATH_MAX];
        if (prefix[0] == '\0') snprintf(path, sizeof(path), "%s", c->name);
        else snprintf(path, sizeof(path), "%s/%s", prefix, c->name);

        SnapEntry key;
        memset(&key, 0, sizeof(key));
        key.path = path;
        SnapEntry *found = (SnapEntry *)bsearch(&key, t->items, t->n,
                                                 sizeof(SnapEntry), snapentry_cmp);
        if (found) {
            c->diff_checked = true;
            bool changed;
            if (c->is_dir != found->is_dir) {
                changed = true;
            } else if (c->hash_len > 0 && found->hash_len == c->hash_len) {
                changed = memcmp(c->hash, found->hash, c->hash_len) != 0;
            } else {
                changed = (c->size_bytes != found->size) || (c->mtime != found->mtime);
            }
            c->modified = changed;
        }
        if (c->is_dir) mark_diff_recursive(c, path, t);
    }
}

HashAlgo diff_peek_algo(const char *snapshot_path) {
    FILE *f = fopen(snapshot_path, "rb");
    if (!f) return HASH_ALGO_NONE;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return HASH_ALGO_NONE; }
    char *buf = (char *)malloc((size_t)sz + 1);
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[rd] = '\0';

    JVal *doc = json_parse(buf);
    free(buf);
    if (!doc) return HASH_ALGO_NONE;
    HashAlgo algo = hash_algo_from_name(json_as_string(json_obj_get(doc, "hash_algo")));
    json_free(doc);
    return algo;
}

HashAlgo diff_apply(const char *snapshot_path, Node *root) {
    FILE *f = fopen(snapshot_path, "rb");
    if (!f) return HASH_ALGO_NONE;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return HASH_ALGO_NONE; }
    char *buf = (char *)malloc((size_t)sz + 1);
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[rd] = '\0';

    JVal *doc = json_parse(buf);
    free(buf);
    if (!doc) return HASH_ALGO_NONE;

    HashAlgo algo = hash_algo_from_name(json_as_string(json_obj_get(doc, "hash_algo")));

    SnapTable t;
    memset(&t, 0, sizeof(t));
    flatten_snapshot_root(json_obj_get(doc, "tree"), &t);
    if (t.n) qsort(t.items, t.n, sizeof(SnapEntry), snapentry_cmp);

    mark_diff_recursive(root, "", &t);

    for (size_t i = 0; i < t.n; i++) free(t.items[i].path);
    free(t.items);
    json_free(doc);
    return algo;
}
