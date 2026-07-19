/* &desc: "Implements save_output: creates .ltree/ if needed and writes a timestamped, always-full-data JSON snapshot (immune to -jE/-jI filtering and to whatever -o this run passed) via the same json_render() the -j path uses." */
#define _GNU_SOURCE
#include "io/save.h"
#include "io/json.h"
#include "io/diff.h"
#include "util/util.h"
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
     * "different" even when the scanned content hasn't changed. Same
     * reasoning for stdout_filter and modules[]: neither -jE/-jI nor
     * plain -o govern what THIS run's snapshot needs -- a snapshot
     * missing HASH because this run happened to pass `-jE HASH` (or
     * just didn't pass `-o HASH` at all, now that plain -j/-jL mirror
     * -o) would silently break a later -o DIFF run forever. Forcing
     * every module bit true here, on a local copy, keeps the snapshot
     * always the full data regardless of what this run's own stdout
     * asked for. */
    Config snap_cfg = *cfg;
    snap_cfg.stdout_filter = STDOUT_FILTER_NONE;
    for (int m = 0; m < MOD_COUNT; m++) snap_cfg.modules[m] = true;
    json_render(&sb, root, display_path, tot, ext, &snap_cfg, NULL);
    fwrite(sb.data, 1, sb.len, f);
    sbuf_free(&sb);
    fclose(f);

    fprintf(stderr, "saved snapshot: %s\n", path);
    return true;
}
