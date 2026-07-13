# Architecture

`ltree` is a small multi-file C project, no external dependencies --
just libc + POSIX (`dirent`, `mmap`, `fnmatch`). Every `.c` file under
`src/` is compiled together into one binary; there's no library
boundary, just a module boundary kept by convention (each `.c` file
has a matching `.h` that other modules `#include`).

## The one-paragraph version

We walk the filesystem exactly once (`scan.c`), building an in-memory
`Node` tree with every stat/line/char/hash field already filled in.
Everything downstream -- the aligned tree view (`render_tree.c`), the
`FILES`-by-extension summary (`render_files.c`), JSON export
(`json.c`), `--save-output` (`save.c`), and `-o DIFF` (`diff.c`) -- is
just a different way of reading that same tree. No module re-stats,
re-mmaps, or re-hashes a file that `scan.c` already touched.

## Module map

| File | Responsibility |
|---|---|
| `main.c` | CLI parsing and orchestration: builds `Config`, resolves which hash algorithm the run actually needs (see `docs/plan.md`), calls `build_tree`, dispatches to the right output path(s), frees everything. |
| `config.h` | The `Config` struct -- the fully-parsed command line, passed as `const Config *cfg` to every module that needs a flag. Only `main.c` ever writes to it. Also defines `HashAlgo`. |
| `node.h` / `node.c` | The in-memory tree (`Node`). Fixed-size fields only (`mode_t`/`int64_t`/`time_t`/byte array) -- formatting to text happens at print time, never stored. `node_cmp` gives the case-insensitive alphabetical ordering used everywhere. |
| `scan.h` / `scan.c` | The one filesystem walk. `build_tree` recurses, applying `--exclude`/`--gitignore`, respecting `-L`/`-d`, and -- in a single `mmap` + linear pass per file -- counts lines, counts UTF-8 chars, and (if needed) hashes the file's bytes. Directory hashes are combined from already-computed child hashes, no re-reading involved. |
| `exttable.h` / `exttable.c` | Per-extension accumulator (files/lines/chars), used by both the terminal `FILES:` section and the JSON `by_extension` block, so they can never drift apart. Also owns `file_ext()` / `strip_ext_for_display()` (the default `-o EXT`-hidden display logic). |
| `gitignore.h` / `gitignore.c` | Reads and matches a single root-level `.gitignore` (documented subset of real gitignore semantics -- see `docs/usage.md`). Composes with `--exclude` inside `scan.c`'s `is_excluded()`. |
| `hash.h` / `hash.c` | xxHash64 and SHA-256, both implemented from the published spec/reference constants -- no external hashing library. One dispatch API (`hash_compute`) both algorithms sit behind, plus `hash_combine_children()` for directory digests. |
| `render_tree.h` / `render_tree.c` | The aligned tree view. Flattens the `Node` tree into printable lines in one pass, measures every active `-o` module's column width in a second pass, then prints with the fixed 3-space gap / 8-space name padding described in `docs/usage.md`. Also renders the `TOTAL:` summary and the "no snapshot" `DIFF` note. |
| `render_files.h` / `render_files.c` | The `FILES:` by-extension summary table, sorted by line count descending. |
| `debug.h` / `debug.c` | `-o DEBUG` support: collects a hyper-detailed `DebugStats` struct once (`debug_collect`, called from `main.c` right before output) -- timing (`clock_gettime` marks taken in `main.c`), `getrusage` (peak RSS, page faults, context switches), `mallinfo2` (heap arena breakdown), and an estimate of the `Node` tree's own memory footprint -- then renders it two ways: `debug_print_text()` for the tree view's `DEBUG:` block, `debug_json_append()` for the JSON `"debug"` object. Neither output path recomputes anything; both just format the same struct. Deliberately never passed to `save.c`'s `json_render()` call, so `--save-output` snapshots never carry this ephemeral per-run data. |
| `util.h` / `util.c` | Small, dependency-free helpers shared everywhere: the growable string builder (`SBuf`, used by `json.c`), UTF-8 display-width counting (used for column alignment), and the `PERMISSIONS`/`SIZE`/`DATE`/hash-hex formatting helpers. Deliberately has zero dependency on `Node` or `Config` to avoid circularity. |
| `colors.h` | The ANSI palette. `COL()`/`RST()` macros collapse to `""` under `--no-colour`, so print sites never branch on that flag themselves. |
| `json.h` / `json.c` | Two things in one file: (1) the JSON *writer* (`json_render`/`print_json`), used by both `-j` and `--save-output` so they never drift apart; (2) a minimal recursive-descent JSON *reader*, just enough to parse ltree's own snapshot files back in for `-o DIFF` -- not a general-purpose validator. |
| `diff.h` / `diff.c` | `-o DIFF` support: finds the newest `.ltree/*.json` snapshot, flattens it into a sorted-by-path table (so comparison is a `bsearch`, not a parallel tree walk -- trees can differ in shape when files were added/removed), and marks `Node.modified` on anything that differs. |
| `save.h` / `save.c` | `--save-output`: creates `.ltree/` if needed and writes a timestamped JSON snapshot via the same `json_render()` the `-j` path uses. |

## Data flow

```
        scan.c (one walk)
             |
             v
        Node tree  ---------------------------+
             |                                 |
    +--------+--------+------------+           |
    v                  v            v           v
render_tree.c    render_files.c  json.c      diff.c (reads a
(terminal view)  (FILES: block)  (writer)     PAST json.c
     ^                              |         snapshot back
     |                              v         via json.c's
     +----- debug.c (DebugStats) save.c       reader, marks
            (-o DEBUG, text+json  (--save-output,  Node.modified)
             via same struct;    debug always
             never passed to     NULL here)
             save.c)
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
