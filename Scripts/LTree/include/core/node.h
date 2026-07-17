/* &desc: "Defines the in-memory Node tree struct (fixed-size stat/line/char/hash/btime fields filled once by scan.c, formatted to text only at print time) and declares node_cmp, the case-insensitive alphabetical ordering used by default everywhere." */
/* node.h -- the in-memory tree. One filesystem walk (scan.c) fills
 * every field exactly once; everything downstream (render_tree.c,
 * render_files.c, json.c, diff.c) just reads it back in different
 * shapes. Fixed-size fields only (mode_t/int64_t/time_t/byte array)
 * -- formatting to text happens at print time, never stored. */
#ifndef LTREE_NODE_H
#define LTREE_NODE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include "hash/hash.h"

typedef struct Node {
    char        *name;       /* basename                                  */
    bool         is_dir;
    bool         is_symlink;
    bool         truncated;  /* dir hit max-depth: exists, not expanded   */

    long         lines;      /* file: own count. dir: sum of DIRECT kids  */
    long         chars;

    mode_t       mode;       /* permission bits, from stat()               */
    int64_t      size_bytes; /* file: st_size. dir: sum of DIRECT kids     */
    time_t       mtime;      /* file/dir: own st_mtime (never aggregated)  */
    time_t       btime;      /* file/dir: creation time via statx()
                               * STATX_BTIME, falls back to mtime when the
                               * filesystem/kernel doesn't report one --
                               * see scan.c. Used by --sort birth.         */

    uint8_t      hash[HASH_MAX_BYTES];
    uint8_t      hash_len;   /* 0 = not computed, 8 = xxhash64, 32 = sha256*/

    bool         diff_checked; /* -o DIFF compared this node against a snapshot */
    bool         modified;     /* -o DIFF: differs from the loaded snapshot     */

    struct Node **children;
    size_t       nchildren;
    size_t       children_cap;
} Node;

Node *node_new(const char *name, bool is_dir);
void  node_add_child(Node *parent, Node *child);
void  node_free(Node *n);

/* case-insensitive alphabetical, dirs and files interleaved (qsort cmp) */
int node_cmp(const void *a, const void *b);

#endif
