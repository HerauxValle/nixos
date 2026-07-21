/* &desc: "Implements -o DEBUG's DebugTimer checkpoints and debug_collect (getrusage/mallinfo2/clock_gettime-based DebugStats collection), plus its two renderers, debug_print_text and debug_json_append." */
#define _GNU_SOURCE
#include "debug/debug.h"
#include "hash/hash.h"
#include "render/colors.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/resource.h>
#include <sys/types.h>
#if defined(__APPLE__)
#include <malloc/malloc.h>
#else
#include <malloc.h>
#endif

/* ===================== timing ============================================ */
void debug_timer_mark_start(DebugTimer *t)      { clock_gettime(CLOCK_MONOTONIC, &t->program_start); }
void debug_timer_mark_scan_start(DebugTimer *t) { clock_gettime(CLOCK_MONOTONIC, &t->scan_start); }
void debug_timer_mark_scan_end(DebugTimer *t)   { clock_gettime(CLOCK_MONOTONIC, &t->scan_end); }

static double ts_diff_seconds(struct timespec a, struct timespec b) {
    /* b - a, both CLOCK_MONOTONIC, b assumed >= a */
    return (double)(b.tv_sec - a.tv_sec) + (double)(b.tv_nsec - a.tv_nsec) / 1e9;
}

/* ===================== tree memory estimate ==============================
 * Not a real allocator introspection (that would need wrapping every
 * malloc/free call site) -- a straightforward walk summing what we
 * know each Node "owns": the struct itself, its name string, and, for
 * directories, the children pointer array. Close enough to be useful
 * for "does adding module X noticeably grow the tree", explicitly
 * documented as an estimate rather than claimed as exact.
 * ===================================================================== */
static long long tree_memory_walk(const Node *n) {
    if (!n) return 0;
    long long bytes = (long long)sizeof(Node);
    bytes += n->name ? (long long)(strlen(n->name) + 1) : 0;
    if (n->is_dir) {
        bytes += (long long)(n->children_cap * sizeof(Node *));
        for (size_t i = 0; i < n->nchildren; i++) bytes += tree_memory_walk(n->children[i]);
    }
    return bytes;
}

static long tree_node_count(const Node *n) {
    if (!n) return 0;
    long count = 1;
    if (n->is_dir) for (size_t i = 0; i < n->nchildren; i++) count += tree_node_count(n->children[i]);
    return count;
}

/* ===================== collect ============================================ */
void debug_collect(DebugStats *out, const DebugTimer *timer, Node *root,
                    const Totals *tot, const Config *cfg) {
    memset(out, 0, sizeof(*out));

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    out->wall_clock_seconds = ts_diff_seconds(timer->program_start, now);
    out->scan_seconds       = ts_diff_seconds(timer->scan_start, timer->scan_end);

    struct rusage ru;
    memset(&ru, 0, sizeof(ru));
    if (getrusage(RUSAGE_SELF, &ru) == 0) {
        out->cpu_user_seconds         = (double)ru.ru_utime.tv_sec + (double)ru.ru_utime.tv_usec / 1e6;
        out->cpu_system_seconds       = (double)ru.ru_stime.tv_sec + (double)ru.ru_stime.tv_usec / 1e6;
#if defined(__APPLE__)
        out->peak_rss_kb           = ru.ru_maxrss / 1024;  /* Darwin reports bytes, not KB */
#else
        out->peak_rss_kb           = ru.ru_maxrss;         /* already KB on Linux */
#endif
        out->minor_page_faults        = ru.ru_minflt;
        out->major_page_faults        = ru.ru_majflt;
        out->block_input_ops          = ru.ru_inblock;
        out->block_output_ops         = ru.ru_oublock;
        out->voluntary_ctx_switches   = ru.ru_nvcsw;
        out->involuntary_ctx_switches = ru.ru_nivcsw;
    }

#if defined(__APPLE__)
    /* No mallinfo2() on Darwin -- malloc_zone_statistics() over the
     * default zone is the nearest equivalent: size_in_use is bytes
     * actually live, size_allocated is what the zone holds overall
     * (in-use + free), so the gap between them stands in for glibc's
     * "free" bucket. Darwin doesn't split out an mmap'd region the
     * way glibc does, so that field is left at 0. */
    malloc_statistics_t mi;
    malloc_zone_statistics(NULL, &mi);
    out->heap_in_use_bytes = (long long)mi.size_in_use;
    out->heap_free_bytes   = (long long)(mi.size_allocated - mi.size_in_use);
    out->heap_mmap_bytes   = 0;
    out->heap_arena_bytes  = (long long)mi.size_allocated;
#else
    struct mallinfo2 mi = mallinfo2();
    out->heap_in_use_bytes = (long long)mi.uordblks;
    out->heap_free_bytes   = (long long)mi.fordblks;
    out->heap_mmap_bytes   = (long long)mi.hblkhd;
    out->heap_arena_bytes  = (long long)mi.arena;
#endif

    out->dirs_scanned  = tot->dirs;
    out->files_scanned = tot->files;
    out->nodes_total    = tree_node_count(root);
    out->tree_memory_bytes_estimate = tree_memory_walk(root);

    if (out->scan_seconds > 0.0 && tot->files > 0) {
        out->files_per_second = (double)tot->files / out->scan_seconds;
        out->avg_us_per_file   = (out->scan_seconds * 1e6) / (double)tot->files;
    }

    snprintf(out->hash_algo, sizeof(out->hash_algo), "%s", hash_algo_name(cfg->hash_algo));
    out->pid             = (long)getpid();
    out->page_size_bytes = sysconf(_SC_PAGESIZE);
}

/* ===================== JSON formatting ==================================== */
void debug_json_append(SBuf *sb, const DebugStats *d) {
    sbuf_append(sb, "  \"debug\": {\n");
    sbuf_appendf(sb, "    \"wall_clock_seconds\": %.6f,\n", d->wall_clock_seconds);
    sbuf_appendf(sb, "    \"scan_seconds\": %.6f,\n", d->scan_seconds);
    sbuf_appendf(sb, "    \"cpu_user_seconds\": %.6f,\n", d->cpu_user_seconds);
    sbuf_appendf(sb, "    \"cpu_system_seconds\": %.6f,\n", d->cpu_system_seconds);
    sbuf_appendf(sb, "    \"peak_rss_kb\": %ld,\n", d->peak_rss_kb);
    sbuf_appendf(sb, "    \"minor_page_faults\": %ld,\n", d->minor_page_faults);
    sbuf_appendf(sb, "    \"major_page_faults\": %ld,\n", d->major_page_faults);
    sbuf_appendf(sb, "    \"block_input_ops\": %ld,\n", d->block_input_ops);
    sbuf_appendf(sb, "    \"block_output_ops\": %ld,\n", d->block_output_ops);
    sbuf_appendf(sb, "    \"voluntary_ctx_switches\": %ld,\n", d->voluntary_ctx_switches);
    sbuf_appendf(sb, "    \"involuntary_ctx_switches\": %ld,\n", d->involuntary_ctx_switches);
    sbuf_appendf(sb, "    \"heap_in_use_bytes\": %lld,\n", d->heap_in_use_bytes);
    sbuf_appendf(sb, "    \"heap_free_bytes\": %lld,\n", d->heap_free_bytes);
    sbuf_appendf(sb, "    \"heap_mmap_bytes\": %lld,\n", d->heap_mmap_bytes);
    sbuf_appendf(sb, "    \"heap_arena_bytes\": %lld,\n", d->heap_arena_bytes);
    sbuf_appendf(sb, "    \"dirs_scanned\": %ld,\n", d->dirs_scanned);
    sbuf_appendf(sb, "    \"files_scanned\": %ld,\n", d->files_scanned);
    sbuf_appendf(sb, "    \"nodes_total\": %ld,\n", d->nodes_total);
    sbuf_appendf(sb, "    \"tree_memory_bytes_estimate\": %lld,\n", d->tree_memory_bytes_estimate);
    sbuf_appendf(sb, "    \"files_per_second\": %.2f,\n", d->files_per_second);
    sbuf_appendf(sb, "    \"avg_us_per_file\": %.2f,\n", d->avg_us_per_file);
    sbuf_append(sb, "    \"hash_algo\": "); sbuf_append_json_string(sb, d->hash_algo); sbuf_append(sb, ",\n");
    sbuf_appendf(sb, "    \"pid\": %ld,\n", d->pid);
    sbuf_appendf(sb, "    \"page_size_bytes\": %ld\n", d->page_size_bytes);
    sbuf_append(sb, "  }");
}

/* ===================== text formatting ==================================== */
void debug_print_text(const DebugStats *d, const Config *cfg) {
    /* Header shares TOTAL:/FILES:'s colour (ANSI_TOTAL) so all three
     * summary-section headers read as one family, the same way EXT
     * accents FILES:'s per-row extension name. Sub-dividers use
     * ANSI_DEBUG as a second-tier accent -- same idea, one level down.
     * Values reuse the exact hues the tree's own L/C/P/S/D/H columns
     * already carry, grouped by what kind of number they are, so
     * DEBUG: doesn't read as a disconnected block of plain text: */
    const char *C  = COL(cfg, ANSI_TOTAL);  /* top header    */
    const char *SC = COL(cfg, ANSI_DEBUG);  /* sub-dividers  */
    const char *TM = COL(cfg, ANSI_DATE);   /* timing values -- same dim as D: (time-flavoured) */
    const char *MEM= COL(cfg, ANSI_SIZE);   /* memory/byte values -- same yellow as S:          */
    const char *CNT= COL(cfg, ANSI_LINES);  /* raw counts -- same green as L:                   */
    const char *HA = COL(cfg, ANSI_HASH);   /* hash algo -- same magenta as H:                  */
    const char *MS = COL(cfg, ANSI_NOTE);   /* misc/system metadata -- same dim as trailing notes*/
    const char *R  = RST(cfg);

    printf("\n%sDEBUG:%s\n", C, R);

    printf("  %s-- timing --%s\n", SC, R);
    printf("  wall clock:              %s%.3f s%s\n", TM, d->wall_clock_seconds, R);
    printf("  scan (walk+hash) time:   %s%.3f s%s\n", TM, d->scan_seconds, R);
    printf("  cpu user / system:       %s%.3f s / %.3f s%s\n", TM, d->cpu_user_seconds, d->cpu_system_seconds, R);
    if (d->files_scanned > 0) {
        printf("  throughput:              %s%.0f files/sec (%.1f us/file avg)%s\n",
               TM, d->files_per_second, d->avg_us_per_file, R);
    }

    printf("  %s-- memory --%s\n", SC, R);
    printf("  peak RSS:                %s%ld KB%s\n", MEM, d->peak_rss_kb, R);
    printf("  heap in use / free:      %s%lld B / %lld B%s\n", MEM, d->heap_in_use_bytes, d->heap_free_bytes, R);
    printf("  heap arena / mmap'd:     %s%lld B / %lld B%s\n", MEM, d->heap_arena_bytes, d->heap_mmap_bytes, R);
    printf("  tree footprint (est.):   %s%lld B across %ld nodes%s\n",
           MEM, d->tree_memory_bytes_estimate, d->nodes_total, R);

    printf("  %s-- OS scheduling / IO --%s\n", SC, R);
    printf("  page faults (min/maj):   %s%ld / %ld%s\n", CNT, d->minor_page_faults, d->major_page_faults, R);
    printf("  block IO (in/out):       %s%ld / %ld%s\n", CNT, d->block_input_ops, d->block_output_ops, R);
    printf("  ctx switches (vol/inv):  %s%ld / %ld%s\n", CNT, d->voluntary_ctx_switches, d->involuntary_ctx_switches, R);

    printf("  %s-- misc --%s\n", SC, R);
    printf("  dirs / files scanned:    %s%ld / %ld%s\n", CNT, d->dirs_scanned, d->files_scanned, R);
    printf("  hash algo:               %s%s%s\n", HA, d->hash_algo, R);
    printf("  pid:                     %s%ld%s\n", MS, d->pid, R);
    printf("  page size:               %s%ld B%s\n", MS, d->page_size_bytes, R);
}
