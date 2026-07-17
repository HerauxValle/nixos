/* &desc: "Implements the stderr-only, tty-gated, rate-limited loading spinner (spinner_start/spinner_tick/spinner_erase/spinner_stop) -- a 10-frame braille glyph redrawn in place via \\r + clear-line, active only when stderr is a terminal." */
#define _GNU_SOURCE
#include "util/spinner.h"
#include <stdio.h>
#include <unistd.h>
#include <time.h>

static const char *FRAMES[] = {
    "\xE2\xA0\x8B", "\xE2\xA0\x99", "\xE2\xA0\xB9", "\xE2\xA0\xB8", "\xE2\xA0\xBC",
    "\xE2\xA0\xB4", "\xE2\xA0\xA6", "\xE2\xA0\xA7", "\xE2\xA0\x87", "\xE2\xA0\x8F",
};
#define FRAME_COUNT (sizeof(FRAMES) / sizeof(FRAMES[0]))
#define TICK_INTERVAL_NS (90L * 1000L * 1000L) /* ~90ms between redraws unless forced */

static bool g_active = false;
static bool g_drawn = false;
static bool g_no_colour = false;
static size_t g_frame = 0;
static struct timespec g_last_tick;

static long ts_diff_ns(const struct timespec *a, const struct timespec *b) {
    return (b->tv_sec - a->tv_sec) * 1000000000L + (b->tv_nsec - a->tv_nsec);
}

void spinner_start(bool no_colour) {
    g_active = isatty(STDERR_FILENO);
    g_drawn = false;
    g_no_colour = no_colour;
    g_frame = 0;
    clock_gettime(CLOCK_MONOTONIC, &g_last_tick);
}

static void draw(void) {
    if (g_no_colour) fprintf(stderr, "\r\x1b[2K%s scanning", FRAMES[g_frame]);
    else              fprintf(stderr, "\r\x1b[2K\x1b[2m%s scanning\x1b[0m", FRAMES[g_frame]);
    fflush(stderr);
    g_drawn = true;
}

void spinner_tick(bool force) {
    if (!g_active) return;

    if (!force) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (ts_diff_ns(&g_last_tick, &now) < TICK_INTERVAL_NS) return;
        g_last_tick = now;
    }

    g_frame = (g_frame + 1) % FRAME_COUNT;
    fflush(stdout); /* keep stdout/stderr from interleaving oddly on a shared tty */
    draw();
}

void spinner_erase(void) {
    if (!g_active || !g_drawn) return;
    fflush(stdout);
    fprintf(stderr, "\r\x1b[2K");
    fflush(stderr);
    g_drawn = false;
}

void spinner_stop(void) {
    if (!g_active) return;
    spinner_erase();
    g_active = false;
}
