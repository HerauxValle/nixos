/* &desc: "Declares the stderr-only, tty-gated loading spinner: spinner_start/spinner_tick/spinner_erase/spinner_stop, used so a scan that takes more than a fraction of a second doesn't look stuck, whether buffered (no --live) or streaming top-down (--live)." */
/* spinner.h -- an animated "still working" indicator for scans that take
 * long enough to notice. Writes only to stderr (never stdout -- keeps -j
 * and piped output byte-for-byte unaffected) and only draws anything when
 * stderr is actually a terminal, so non-interactive runs (scripts,
 * smoke_test.sh) are a no-op by construction.
 *
 * Two ways it's used (see scan/scan.c and render/render_tree.c):
 *   - No --live: build_tree() ticks it once per directory entry
 *     processed. Nothing else prints until the whole walk finishes, so
 *     this is the only thing on screen; spinner_stop() clears it right
 *     before the buffered tree/ls/JSON view prints.
 *   - --live: same per-entry ticking during the walk, PLUS every real
 *     line render_tree.c streams to stdout is wrapped in
 *     spinner_erase() (before) / spinner_tick(true) (after), so the
 *     spinner is always erased before a real line prints and immediately
 *     redrawn underneath it -- it stays "the last line" the whole run.
 *
 * Rate-limited (~90ms) unless forced, so a scan that finishes faster than
 * that never draws anything at all -- no flicker on fast runs. */
#ifndef LTREE_SPINNER_H
#define LTREE_SPINNER_H

#include <stdbool.h>

/* Call once before the scan starts. No-ops (spinner stays inactive for
 * every other call below) unless stderr is a tty. */
void spinner_start(bool no_colour);

/* Redraws the current frame in place (\r + clear-line + glyph). Rate-
 * limited to ~90ms between actual redraws unless `force` is true, which
 * always redraws immediately -- used right after real content prints so
 * the spinner reappears right underneath it without waiting out the
 * interval. */
void spinner_tick(bool force);

/* \r + clear-line, no redraw -- call immediately before printing real
 * content so the spinner's text doesn't corrupt that line. */
void spinner_erase(void);

/* Erases and deactivates. Safe to call even if spinner_start() was never
 * called or already no-op'd (not a tty). */
void spinner_stop(void);

#endif
