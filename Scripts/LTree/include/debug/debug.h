/* &desc: "Declares DebugStats and the DebugTimer/debug_collect/debug_print_text/debug_json_append API behind -o DEBUG's hyper-detailed timing/memory/IO run report, computed once and rendered two ways from the same struct." */
/* debug.h -- -o DEBUG: a hyper-detailed "how did this run go" report.
 * Timing (wall clock + CPU), memory (peak RSS, page faults, glibc
 * heap-arena breakdown, an estimate of the in-memory Node tree's own
 * footprint), I/O and scheduling counters, and derived throughput
 * numbers.
 *
 * Same convention as every other -o module: the numbers are computed
 * exactly once into a plain struct (DebugStats), and both output
 * paths just format that same struct -- debug_json_append() for `-j`,
 * debug_print_text() for the tree view. Neither path recomputes
 * anything; JSON is the canonical shape, text is just a different
 * rendering of it (see json.c's total/by_extension blocks for the
 * existing pattern this follows).
 */
#ifndef LTREE_DEBUG_H
#define LTREE_DEBUG_H

#include <time.h>
#include "core/node.h"
#include "scan/scan.h"
#include "core/config.h"
#include "util/util.h"

/* Wall-clock checkpoints, taken with CLOCK_MONOTONIC (immune to
 * system-clock adjustments mid-run) at fixed points in main()'s
 * execution. Plain struct, no hidden state -- main.c owns it. */
typedef struct {
    struct timespec program_start;   /* first thing in main()            */
    struct timespec scan_start;      /* immediately before build_tree()  */
    struct timespec scan_end;        /* immediately after build_tree()   */
} DebugTimer;

typedef struct {
    /* ---- timing ---- */
    double wall_clock_seconds;       /* program_start -> debug_collect() */
    double scan_seconds;             /* scan_start -> scan_end           */
    double cpu_user_seconds;         /* getrusage ru_utime               */
    double cpu_system_seconds;       /* getrusage ru_stime               */

    /* ---- OS-level memory / scheduling (getrusage) ---- */
    long   peak_rss_kb;              /* ru_maxrss (already KB on Linux)  */
    long   minor_page_faults;        /* ru_minflt                        */
    long   major_page_faults;        /* ru_majflt -- real disk I/O stalls*/
    long   block_input_ops;          /* ru_inblock                       */
    long   block_output_ops;         /* ru_oublock                       */
    long   voluntary_ctx_switches;   /* ru_nvcsw                         */
    long   involuntary_ctx_switches; /* ru_nivcsw                        */

    /* ---- glibc malloc arena (mallinfo2) ---- */
    long long heap_in_use_bytes;     /* uordblks -- actually allocated   */
    long long heap_free_bytes;       /* fordblks -- held but free        */
    long long heap_mmap_bytes;       /* hblkhd   -- large allocs via mmap*/
    long long heap_arena_bytes;      /* arena    -- total sbrk'd arena   */

    /* ---- scan-derived ---- */
    long   dirs_scanned;
    long   files_scanned;
    long   nodes_total;
    long long tree_memory_bytes_estimate; /* Node structs + names + child arrays */
    double files_per_second;
    double avg_us_per_file;

    /* ---- misc ---- */
    char   hash_algo[16];
    long   pid;
    long   page_size_bytes;
} DebugStats;

void debug_timer_mark_start(DebugTimer *t);
void debug_timer_mark_scan_start(DebugTimer *t);
void debug_timer_mark_scan_end(DebugTimer *t);

/* Fills *out. Call right before rendering output, so wall_clock_seconds
 * covers "real work done" (scanning, hashing, diffing) rather than
 * printing time. */
void debug_collect(DebugStats *out, const DebugTimer *timer, Node *root,
                    const Totals *tot, const Config *cfg);

/* Appends `"debug": { ... }` -- no leading/trailing comma of its own,
 * json_render() manages separators between top-level blocks itself
 * (needed since --stdout filtering means any subset of blocks can be
 * present). Call site must only call this when it actually wants the
 * block present. */
void debug_json_append(SBuf *sb, const DebugStats *d);

/* Prints the "DEBUG:" text block, same visual style as TOTAL:. */
void debug_print_text(const DebugStats *d, const Config *cfg);

#endif
