#define _GNU_SOURCE
#include "save.h"
#include "json.h"
#include "diff.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <errno.h>

bool save_output(Node *root, const char *display_path, const Totals *tot,
                  const ExtTable *ext, const Config *cfg) {
    char *dir = ltree_snapshot_dir(cfg);

    if (mkdir(dir, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "warning: could not create %s: %s\n", dir, strerror(errno));
        free(dir);
        return false;
    }

    char timestamp[32];
    format_timestamp_filename(time(NULL), timestamp, sizeof(timestamp));

    char path[4096];
    snprintf(path, sizeof(path), "%s/%s.json", dir, timestamp);
    free(dir);

    FILE *f = fopen(path, "w");
    if (!f) {
        fprintf(stderr, "warning: could not write %s: %s\n", path, strerror(errno));
        return false;
    }

    SBuf sb;
    sbuf_init(&sb);
    /* dbg is intentionally NULL here: --save-output snapshots are
     * meant to be diffed against each other later, and per-run
     * timing/RSS/pid noise would make every snapshot spuriously
     * "different" even when the scanned content hasn't changed. */
    json_render(&sb, root, display_path, tot, ext, cfg, NULL);
    fwrite(sb.data, 1, sb.len, f);
    sbuf_free(&sb);
    fclose(f);

    fprintf(stderr, "saved snapshot: %s\n", path);
    return true;
}
