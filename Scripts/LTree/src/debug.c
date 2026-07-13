#define _GNU_SOURCE
#include "debug.h"
#include "hash.h"
#include "colors.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <malloc.h>

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
        out->peak_rss_kb              = ru.ru_maxrss;      /* already KB on Linux */
        out->minor_page_faults        = ru.ru_minflt;
        out->major_page_faults        = ru.ru_majflt;
        out->block_input_ops          = ru.ru_inblock;
        out->block_output_ops         = ru.ru_oublock;
        out->voluntary_ctx_switches   = ru.ru_nvcsw;
        out->involuntary_ctx_switches = ru.ru_nivcsw;
    }

    struct mallinfo2 mi = mallinfo2();
    out->heap_in_use_bytes = (long long)mi.uordblks;
    out->heap_free_bytes   = (long long)mi.fordblks;
    out->heap_mmap_bytes   = (long long)mi.hblkhd;
    out->heap_arena_bytes  = (long long)mi.arena;

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
    sbuf_append(sb, "  },\n");
}

/* ===================== text formatting ==================================== */
void debug_print_text(const DebugStats *d, const Config *cfg) {
    printf("\n%sDEBUG:%s\n", COL(cfg, ANSI_DEBUG), RST(cfg));
    printf("  -- timing --\n");
    printf("  wall clock:              %.3f s\n", d->wall_clock_seconds);
    printf("  scan (walk+hash) time:   %.3f s\n", d->scan_seconds);
    printf("  cpu user / system:       %.3f s / %.3f s\n", d->cpu_user_seconds, d->cpu_system_seconds);
    if (d->files_scanned > 0) {
        printf("  throughput:              %.0f files/sec (%.1f us/file avg)\n",
               d->files_per_second, d->avg_us_per_file);
    }
    printf("  -- memory --\n");
    printf("  peak RSS:                %ld KB\n", d->peak_rss_kb);
    printf("  heap in use / free:      %lld B / %lld B\n", d->heap_in_use_bytes, d->heap_free_bytes);
    printf("  heap arena / mmap'd:     %lld B / %lld B\n", d->heap_arena_bytes, d->heap_mmap_bytes);
    printf("  tree footprint (est.):   %lld B across %ld nodes\n",
           d->tree_memory_bytes_estimate, d->nodes_total);
    printf("  -- OS scheduling / IO --\n");
    printf("  page faults (min/maj):   %ld / %ld\n", d->minor_page_faults, d->major_page_faults);
    printf("  block IO (in/out):       %ld / %ld\n", d->block_input_ops, d->block_output_ops);
    printf("  ctx switches (vol/inv):  %ld / %ld\n", d->voluntary_ctx_switches, d->involuntary_ctx_switches);
    printf("  -- misc --\n");
    printf("  dirs / files scanned:    %ld / %ld\n", d->dirs_scanned, d->files_scanned);
    printf("  hash algo:               %s\n", d->hash_algo);
    printf("  pid:                     %ld\n", d->pid);
    printf("  page size:               %ld B\n", d->page_size_bytes);
}
