<!-- &desc: "Explains how ltree's C source is organized into seven subsystem subdirectories (core/scan/hash/render/io/debug/sort/util) plus main.c, with a per-file responsibility table and a data-flow diagram from the single filesystem walk to every output path." -->

# Architecture

`ltree` is a small multi-file C project, no external dependencies --
just libc + POSIX (`dirent`, `mmap`, `fnmatch`). Every `.c` file under
`src/` is compiled together into one binary; there's no library
boundary, just a module boundary kept by convention (each `.c` file
has a matching `.h` that other modules `#include`). Headers live under
`include/`, implementation under `src/`, both grouped into the same
seven subsystem subdirectories:

| Subdir | Holds |
|---|---|
| `core/` | `config.h`/`node.h`/`node.c`/`modules.h`/`modules.c` -- the `Config` struct, the `Node` tree, and the shared `-o` module table everything else (CLI parsing, every renderer) reads from instead of each keeping its own list. |
| `scan/` | `scan.*`, `gitignore.*`, `exttable.*` -- the filesystem walk and everything that filters/accumulates during it. |
| `hash/` | `hash.*` -- xxHash64 + SHA-256. |
| `render/` | `columns.*` (shared column-rendering pipeline), `render_tree.*` (the recursive tree view -- buffered by default, `--live` streams it), `render_ls.*` (default non-recursive `[Folders]`/`[Files]` view, packs into an `ls`-style grid on a tty), `render_files.*`, `colors.h` -- turning a `Node` tree into terminal output, one file per output *mode*, all built on `columns.*`. |
| `io/` | `json.*`, `save.*`, `diff.*` -- JSON read/write and everything built on top of it (snapshots, diffing). |
| `debug/` | `debug.*` -- `-o DEBUG` support. |
| `util/` | `util.*` -- dependency-free shared helpers (`SBuf`, UTF-8 width, formatting). |
| `sort/` | `sortmodes.*` -- `--sort`'s mode parsing and `qsort` comparator, ls-mode only. |

`main.c` is the only file that stays directly under `src/` -- it's the
entry point, not part of any one subsystem. Includes are always
subdir-qualified (`#include "core/node.h"`, never a bare
`"node.h"`), and the build compiles `src/*.c src/*/*.c` with
`-Iinclude`, so this is purely a directory-layout convention (fewer
files per directory as the project grew past ~15 files each) -- the
module boundaries below are unchanged.

## The one-paragraph version

We walk the filesystem exactly once (`scan.c`), building an in-memory
`Node` tree with every stat/line/char/hash/btime field already filled
in. By default, everything downstream -- the recursive tree view
(`render_tree.c`), the default non-recursive listing (`render_ls.c`),
the `FILES`-by-extension summary (`render_files.c`), JSON export
(`json.c`), `--save-output` (`save.c`), and `-o DIFF` (`diff.c`) -- is
just a different way of reading that same, complete tree, once the
walk finishes. No module re-stats, re-mmaps, or re-hashes a file that
`scan.c` already touched. **`--live` is the one exception to "walk
finishes, then render":** it streams `-o TREE`'s output instead.
`scan.c`'s `build_tree()` takes three optional hooks (measure a
directory's columns once, print each entry interleaved with recursing
into it, free per-directory state once that whole subtree is done --
see `scan.h`), which `render_tree.c` wires up only when `--live` is
passed, printing connector-tree lines the instant each directory is
scanned (fixed-width columns, since the rest of the tree isn't known
yet) instead of waiting for the whole walk and whole-tree-aligning
against it.

## Module map

| File | Responsibility |
|---|---|
| `main.c` | CLI parsing and orchestration: builds `Config`, resolves which hash algorithm the run actually needs (see `docs/plan.md`), calls `build_tree`, dispatches to the right output path(s), frees everything. |
| `config.h` | The `Config` struct -- the fully-parsed command line, passed as `const Config *cfg` to every module that needs a flag. Only `main.c` ever writes to it. Also defines `HashAlgo`. |
| `modules.h` / `modules.c` | The shared `-o` module table (`ModuleId`, `ModuleCat`, `MODULE_TABLE`, `module_lookup()`) -- one source of truth `main.c`'s CLI parser and every renderer read from, replacing what used to be a hand-duplicated module list in each. |
| `node.h` / `node.c` | The in-memory tree (`Node`). Fixed-size fields only (`mode_t`/`int64_t`/`time_t`/byte array) -- formatting to text happens at print time, never stored. `node_cmp` gives the case-insensitive alphabetical ordering used everywhere by default. |
| `scan.h` / `scan.c` | The one filesystem walk. `build_tree` recurses, applying `--exclude`/`--gitignore`/`-o HIDDEN`, respecting `-L`/`-d` (ls-mode forces effective depth 0 from `main.c`), and -- in a single `mmap` + linear pass per file -- counts lines, counts UTF-8 chars, and (if needed) hashes the file's bytes. Also fetches birth time (`fetch_btime`, `--sort birth`) via `statx()`. Directory hashes are combined from already-computed child hashes, no re-reading involved. Takes three optional streaming hooks (`on_dir_measure`/`on_entry_ready`/`on_dir_done`), interleaved into the recursion itself, that `main.c` only wires up when `--live` is passed. |
| `exttable.h` / `exttable.c` | Per-extension accumulator (files/lines/chars), used by the terminal `FILES:` section, the JSON `by_extension` block, and `--sort types`'s bucketing, so they can never drift apart. Also owns `file_ext()` / `strip_ext_for_display()` (the default `-o EXT`-hidden display logic). |
| `gitignore.h` / `gitignore.c` | Reads and matches a single root-level `.gitignore` (documented subset of real gitignore semantics -- see `docs/usage.md`). Composes with `--exclude` inside `scan.c`'s `is_excluded()`. |
| `hash.h` / `hash.c` | xxHash64 and SHA-256, both implemented from the published spec/reference constants -- no external hashing library. One dispatch API (`hash_compute`) both algorithms sit behind, plus `hash_combine_children()` for directory digests. |
| `columns.h` / `columns.c` | The shared column-rendering pipeline: `PrintLine`/`LineBuf` (one flattened printable row), `columns_measure()`/`columns_measure_fixed()`/`columns_print_line()` (the two-pass "measure every active LINES/CHARS/PERMISSIONS/SIZE/DATE/HASH column's width -- actual widest value, or a fixed constant for `--live` -- then print aligned" logic, `--condense`/`-o O` aware; `columns_print_line`'s padding is clamped against underflow, since a fixed width a value happens to exceed would otherwise wrap a `size_t` subtraction into a huge pad count), and `print_summary_tail()` (the shared `TOTAL:`/`DEBUG:`/DIFF-note tail both `render_tree.c` and `render_ls.c` -- and `main.c` directly, after `--live` finishes streaming -- call). Everything terminal-output-shaped funnels through here. |
| `render_tree.h` / `render_tree.c` | Two renderers for `-o TREE`: `print_tree_view` (default) flattens the complete tree into one `LineBuf` and whole-tree-aligns it, same convention as `render_ls.c`. `tree_live_*` (`--live`) is wired up as `scan.c`'s three hooks instead: `tree_live_on_dir_measure` sizes a directory's columns via `columns_measure_fixed` (fixed width, not measured -- the rest of the tree isn't known yet), `tree_live_on_entry_ready` prints each entry interleaved with recursion (a per-depth prefix, threaded via a plain array since siblings fully complete their own subtrees before the next one starts, gives correct connector glyphs without buffering), `tree_live_on_dir_done` frees that directory's measurement. |
| `render_ls.h` / `render_ls.c` | The default (no `-o TREE`) view: `root`'s direct children only, grouped into `[Folders]`/`[Files]`, `--sort`/`-o HIDDEN`-aware, `--sort types`'s `[ext]` sub-header bucketing. On a terminal with no `-o` data column active, packs each block into a real `ls -C`-style multi-column grid (`print_grid`) instead of one-per-line. Also built on `columns.c`. |
| `render_files.h` / `render_files.c` | The `FILES:` by-extension summary table (`[TYPE: x] [FILES: n] [LINES: n] [CHARS: n]`, one bracket per column, sorted by line count descending). |
| `debug.h` / `debug.c` | `-o DEBUG` support: collects a hyper-detailed `DebugStats` struct once (`debug_collect`, called from `main.c` right before output) -- timing (`clock_gettime` marks taken in `main.c`), `getrusage` (peak RSS, page faults, context switches), `mallinfo2` (heap arena breakdown), and an estimate of the `Node` tree's own memory footprint -- then renders it two ways: `debug_print_text()` for the `DEBUG:` block, `debug_json_append()` for the JSON `"debug"` object (no leading/trailing comma of its own -- `json_render()` manages all top-level separators, since `--stdout` filtering means any subset of blocks can be present). Neither output path recomputes anything; both just format the same struct. Deliberately never passed to `save.c`'s `json_render()` call, so `--save-output` snapshots never carry this ephemeral per-run data. |
| `util.h` / `util.c` | Small, dependency-free helpers shared everywhere: the growable string builder (`SBuf`, used by `json.c`), UTF-8 display-width counting (used for column alignment), the `PERMISSIONS`/`SIZE`/`DATE`/hash-hex formatting helpers, and `utf8_count_visible_chars()` -- the `CHARS` module's codepoint decoder, which skips combining marks/variation selectors/ZWJ and collapses emoji flag pairs so the count reads as "visible characters" rather than raw codepoints (see `docs/usage.md`). Deliberately has zero dependency on `Node` or `Config` to avoid circularity. |
| `colors.h` | The ANSI palette. `COL()`/`RST()` macros collapse to `""` under `--no-colour`, so print sites never branch on that flag themselves. |
| `json.h` / `json.c` | Two things in one file: (1) the JSON *writer* (`json_render`/`print_json`), used by both `-j` and `--save-output` so they never drift apart -- `json_key_allowed()` gates every optional top-level/per-entry field through `--stdout`'s exclusive/inclusive filter; (2) a minimal recursive-descent JSON *reader*, just enough to parse ltree's own snapshot files back in for `-o DIFF` -- not a general-purpose validator. |
| `diff.h` / `diff.c` | `-o DIFF` support: finds the newest `.ltree/*.json` snapshot, flattens it into a sorted-by-path table (so comparison is a `bsearch`, not a parallel tree walk -- trees can differ in shape when files were added/removed), and marks `Node.modified` on anything that differs. |
| `save.h` / `save.c` | `--save-output`: creates `.ltree/` if needed and writes a timestamped JSON snapshot via the same `json_render()` the `-j` path uses, with a local `Config` copy forcing `stdout_filter` off so a snapshot is always complete regardless of any `--stdout` filtering on the run that wrote it. |
| `sortmodes.h` / `sortmodes.c` | `--sort`'s mode parsing (`sort_parse`) and `qsort` comparator (`sort_nodes`) -- `abc`/`birth`/`modified`/`lines`/`chars`/`types` base modes plus `combined`/`reversed` modifiers. ls-mode only; `render_tree.c` doesn't use this. |

## Data flow

`--live` is the one path that doesn't fit the usual "walk finishes,
then render" shape, so it's shown separately:

```
--live:  scan.c's build_tree() walk
              |
              | on_dir_measure / on_entry_ready / on_dir_done fire
              | DURING the walk, interleaved with the recursion itself
              v
          render_tree.c's tree_live_* prints connector-tree lines
          top-down, fixed-width columns, as each directory is
          scanned -- nothing buffered
```

Every other output path (including `-o TREE`'s default, buffered
form) reads the complete, already-built tree once the walk finishes:

```
        scan.c's build_tree() walk (finished)
                       |
                       v
                   Node tree
    +---------+-------+------------+------------+------------+
    v         v       v            v            v            v
render_tree.c render_ls.c  render_files.c      json.c   (--live already
(-o TREE,     (default,    (FILES: block)     (writer)   streamed, see
buffered)     ls -C grid        |                |         above)
    \         on a tty)         v                v
     \             /       debug.c ------> save.c (--save-output:
      \           /       (-o DEBUG,        debug always NULL,
       \         /         text+json          stdout_filter forced
        +-- columns.c (shared via same          off)
            column measure/    struct)              |
            print pipeline)                         v
                ^                                diff.c (reads a PAST
                |                                  json.c snapshot back
            sortmodes.c (--sort,                   via json.c's reader,
             ls-mode only)                          marks Node.modified)
```

## Why split into modules instead of one file

The project started as a single `src/ltree.c`. Once `PERMISSIONS`,
`SIZE`, `DATE`, `EXT`, `HASH`, `--gitignore`, `--save-output`, and
`-o DIFF` were added on top of the original line/char counter and
JSON exporter, a single file stopped being the readable option --
each feature has its own natural boundary (scanning vs. rendering vs.
persistence vs. comparison) and several of those boundaries
(`json.c`'s writer/reader, `hash.c`'s two algorithms) are reused by
more than one feature. Splitting keeps each file's job nameable in one
sentence, at the cost of one extra header per module -- a fair trade
for a project this size. See `docs/plan.md` for the actual design
session this decision came out of.
