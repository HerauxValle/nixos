<!-- &desc: "Project pitch, build instructions (plain gcc or Nix), full usage summary with examples, and two changelog sections covering the original feature build-out and the later ls-mode rework." -->

# LTree

A directory-listing tool that counts lines and characters per
file/dir, shows permissions/size/last-modified, hashes and diffs a
directory against its last scan, does it fast (mmap + memchr, single
filesystem walk), and can dump the same information as JSON instead of
a pretty-printed listing.

No-args `ltree` behaves like plain `ls` -- one directory, grouped into
`[Folders]`/`[Files]`, packed into a real multi-column grid when
writing to a terminal (piped output, or any `-o` data column, stays
one entry per line). `-o TREE` brings back the classic recursive
connector-tree view instead, whole-tree column aligned, printed once
the walk finishes. `--live` streams it top-down as the walk happens
instead of waiting -- fixed-width columns rather than whole-tree
measured ones, since nothing beyond the current directory is known
yet while it's still scanning.

Zero external dependencies -- straight libc + POSIX (`dirent`,
`mmap`, `fnmatch`, `statx`). Builds the same everywhere with just a C
compiler; the Nix flake exists for reproducibility, not because it
needs anything exotic.

```
$ ltree
testtree
[Folders]
  docs/  src/
[Files]
  README

$ ltree -o LINES,SIZE
testtree
[Folders]
  docs/                       [L: 0]   [S: 6b]
  src/                        [L: 0]   [S: 369b]
[Files]
  README                      [L: 1]   [S: 6b]

$ ltree -o TREE,LINES,CHARS,PERMISSIONS,SIZE,DATE
testtree
├── docs/                       [L: 1]   [C: 6]     [P: drwxr-xr-x]   [S: 6b]     [D: 13-07-2026 21:34:37]
│   ╰── README                  [L: 1]   [C: 6]     [P: -rw-r--r--]   [S: 6b]     [D: 13-07-2026 21:34:37]
╰── src/                        [L: 8]   [C: 300]   [P: drwxr-xr-x]   [S: 369b]   [D: 13-07-2026 21:34:37]
    ├── a.c                     [L: 3]   [C: 24]    [P: -rw-r--r--]   [S: 24b]    [D: 13-07-2026 21:34:37]
    ├── sub1/                   [L: 3]   [C: 252]   [P: drwxr-xr-x]   [S: 318b]   [D: 13-07-2026 21:34:37]
    │   ├── b.py                [L: 2]   [C: 18]    [P: -rw-r--r--]   [S: 18b]    [D: 13-07-2026 21:34:37]
    │   ╰── blob.bin             [L: 1]   [C: 234]   [P: -rw-r--r--]   [S: 300b]   [D: 13-07-2026 21:34:37]
    ╰── sub2/                   [L: 2]   [C: 24]    [P: drwxr-xr-x]   [S: 27b]    [D: 13-07-2026 21:34:37]
        ╰── utf8.txt             [L: 2]   [C: 24]    [P: -rw-r--r--]   [S: 27b]    [D: 13-07-2026 21:34:37]

TOTAL:
  [dirs: 4]   [files: 6]   [lines: 10]   [chars: 312]

FILES:
  [TYPE: c]    [FILES: 1]   [LINES: 3]   [CHARS: 24]
  [TYPE: py]   [FILES: 1]   [LINES: 2]   [CHARS: 18]
  [TYPE: txt]  [FILES: 1]   [LINES: 2]   [CHARS: 24]
  [TYPE: bin]  [FILES: 1]   [LINES: 1]   [CHARS: 234]
  [TYPE: md]   [FILES: 1]   [LINES: 1]   [CHARS: 6]
```

## Build

Plain gcc:

```sh
gcc -O3 -std=c11 -Wall -Wextra -Iinclude -o ltree src/*.c src/*/*.c
```

Or via the flake:

```sh
nix build .#default        # -> result/bin/ltree
nix develop                 # gcc + gdb + valgrind for hacking on it
```

## Usage

```
ltree [path] [options]

  -j                    output JSON instead of a directory listing
  -d                    list directories only
  -L <n>                max depth to descend (like tree -L, -o TREE
                        only), also -L<n>
  -o <MODULES>          comma-separated, any order:
                          LINES, CHARS, TOTAL, FILES,
                          PERMISSIONS, SIZE, DATE, EXT, HASH, DIFF, DEBUG,
                          TREE, HIDDEN
  -o A                  every display module at once (also -oA). Can't
                        be combined with other module names.
  -o E,<MODULES>        every display module EXCEPT the ones listed
                        (also -oE,...). E must come first.
  -o ...,O               (combinable) render columns in the order you
                        typed them in -o, not the fixed L/C/P/S/D/H order
  --exclude <list>      comma-separated names/globs to skip, quote
                        entries with spaces: --exclude "build,*.pyc"
  --gitignore           also exclude what the scan root's .gitignore
                        would (composes with --exclude)
  --cryptographic       -o HASH / -o DIFF use SHA-256 instead of the
                        default xxHash64
  --save-output[=DIR]   write a JSON snapshot to DIR/.ltree/ (default:
                        <path>/.ltree/); filename is a local
                        dd-mm-yyyy_hh:mm:ss timestamp
  --no-colour           disable ANSI colour (also --no-color)
  --condense            one [L:x C:y ...] bracket per entry instead of
                        one bracket per active column
  --live                 -o TREE only: stream top-down as the walk happens
                        instead of waiting for it to finish; fixed-width
                        columns instead of whole-tree-measured ones
  --sort <MODES>        ls-mode only (no effect with -o TREE). One base:
                          abc (default), birth, modified, lines, chars,
                          types -- plus modifiers: combined, reversed
  --stdout <exclusive|inclusive> <MODULES>
                        forces JSON output (like -j) filtered to exclude
                        or keep only the named modules' JSON fields
  -h, --help            this help
```

`path` defaults to `.`; if omitted and stdin isn't a terminal, the
first line read from stdin is used as the path instead. Flags can
appear in any order, including before the path.

Without `-o TREE`, `ltree` lists only `path`'s direct children
(non-recursive, like plain `ls`), grouped into a `[Folders]` block
then a `[Files]` block. On a terminal, with no `-o` data column
active, each block packs into a real multi-column grid the way `ls`
does (piped output, or any active `-o` column, stays one entry per
line). `-o TREE` brings back the full recursive connector-tree view
(respecting `-L`) instead -- everything below about depth/recursion
only applies in that mode. `HIDDEN` shows dotfiles/dot-dirs, hidden by
default like `ls` without `-a`; in ls-mode they're appended after the
visible entries within their own `[Folders]`/`[Files]` block.

`LINES`/`CHARS`/`PERMISSIONS`/`SIZE`/`DATE`/`HASH` each print as their
own aligned `[X: ...]` column per entry, in a fixed order regardless
of the order you list them in `-o` (dirs aggregate
`LINES`/`CHARS`/`SIZE` over their direct children; `PERMISSIONS`/
`DATE` are always the entry's own) -- unless `-o ...,O` is also
present, which switches to rendering columns in the order you actually
typed them. `EXT` toggles showing file extensions in the tree (hidden
by default -- `report.md` shows as `report`). `CHARS` counts *visible*
characters, not raw codepoints -- combining marks, variation
selectors, and zero-width joiners don't add their own count, and an
emoji flag (two regional-indicator codepoints) counts as one, not two.
`DIFF` compares against the newest `.ltree` snapshot, marking changed
entries red with a trailing `[m]`. `TOTAL` and `FILES` are summary
sections appended at the end (same `[X: value]` bracket style as
per-entry columns), not per-entry columns. `DEBUG` prints a
hyper-detailed run report -- timing, peak RSS, heap stats, page
faults, throughput -- right after `TOTAL` (and, in `-j` output, as a
`"debug"` object); it's never written into `--save-output` snapshots,
since it's ephemeral run-to-run noise that would only pollute
diffing. `-o A` (or `-oA`) turns on every display module at once;
`-o E,<list>` (or `-oE,<list>`) turns on every display module *except*
the ones named. Neither counts `TREE`/`HIDDEN` as part of "every
module" -- those change behavior, not what's displayed.

`--sort` only applies in the default ls-mode view (a warning is
printed and it's ignored under `-o TREE`, which keeps plain
alphabetical order). `--sort types` buckets the `[Files]` block into
per-extension `[ext]` sub-headers instead of one flat list.

`-o TREE` is buffered and whole-tree column aligned by default -- the
same "flatten the complete tree, measure every column against the
whole thing, then print" pass every other view uses. `--live` (only
meaningful with `-o TREE`, no effect with `-j`) switches to streaming
instead: each directory's connector-tree lines print the instant that
directory is scanned, top-down, depth-first, instead of waiting for
the whole walk. Since the rest of the tree's shape isn't known yet
while a block is printing, whole-tree alignment isn't possible in
`--live` -- columns use a fixed width and a fixed start position
instead, so output still lines up predictably rather than jaggedly
(an unusually long value just won't line up with what follows it on
that one row). `-o DIFF` can't mark anything on a `--live`-streamed
line either -- diffing needs the complete tree. `TOTAL`/`FILES`/
`DEBUG`/the DIFF note always print once at the end, in either mode.

`--stdout exclusive <MODULES>` / `--stdout inclusive <MODULES>` forces
JSON output filtered to exclude (or keep only) the listed modules'
corresponding JSON keys/fields -- e.g. `--stdout exclusive HASH` omits
the `"hash"` field from every entry, `--stdout inclusive TREE,LINES`
emits only the tree structure with just each entry's `"lines"` field
(plus the always-present `name`/`type`/`symlink`). Never affects
`--save-output` snapshots, which always stay complete so `-o DIFF` has
everything to compare against on a later run.

See [`docs/usage.md`](docs/usage.md) for the full breakdown of every
flag, the exclude/gitignore matching rules, the column-alignment
logic, hashing, and diffing. See
[`docs/json-schema.md`](docs/json-schema.md) for the `-j`/
`--save-output` JSON shape, [`docs/architecture.md`](docs/architecture.md)
for the module map, and [`docs/plan.md`](docs/plan.md) for the design
decisions behind the hashing defaults, timezone choice, and the
module split.

### A few examples

```sh
# just the current dir, ls-style
ltree

# lines + chars + a totals summary, still ls-style
ltree -o LINES,CHARS,TOTAL

# the classic recursive tree, full metadata, gitignore-aware, two levels deep
ltree -o TREE --gitignore -L2 -o LINES,PERMISSIONS,SIZE,DATE

# take a snapshot now, keep working, then see what changed
ltree --save-output
# ... edit some files ...
ltree -o TREE,DIFF,LINES

# JSON, with cryptographic hashes, piped elsewhere
ltree -j -o HASH --cryptographic

# hyper-detailed run report: timing, peak RSS, heap, page faults
ltree -o DEBUG

# everything (display modules) at once
ltree -oA

# everything except HASH and DEBUG
ltree -oE,HASH,DEBUG

# largest files last, files bucketed by extension
ltree --sort lines,types -o LINES

# watch a big recursive scan stream in top-down as it happens
ltree -o TREE --live

# dotfiles included, one compact bracket per entry
ltree -o HIDDEN,LINES,CHARS --condense

# JSON with just the tree + line counts, nothing else
ltree --stdout inclusive TREE,LINES
```

## What changed from the old `countlines.py`

- C instead of Python: one mmap + one `memchr` scan per file instead
  of a Python-level decode; ~1s to walk and count 6000 files / 90MB
  of text under `/usr/include`.
- The tree drawing is a real tree algorithm now (tracks last-child per
  directory) instead of always assuming another sibling is coming --
  branches close off with a rounded corner (`╰──`) instead of just
  trailing away.
- `LINES`/`CHARS`/`TOTAL`/`FILES` are opt-in via `-o`, and when
  requested, columns line up in a straight edge across the *whole*
  tree, not just the current line.
- Native JSON output (`-j`) carries the same tree, so it's easy to
  feed into something else without scraping the pretty-printed text.
- `--exclude` with comma-separated glob patterns, `-d` for dirs-only,
  and depth limiting via `-L`.
- **New:** `PERMISSIONS`, `SIZE`, and `DATE` columns; `EXT` to toggle
  extension display (hidden by default); `--gitignore` support
  (composes with `--exclude`); `HASH` (xxHash64 by default, SHA-256
  via `--cryptographic`); `--save-output` to snapshot a scan as JSON;
  and `DIFF` to compare the current tree against the last snapshot.
- **New:** `DEBUG` -- a hyper-detailed run report (wall clock, CPU
  time, peak RSS, heap-arena breakdown, page faults, throughput) for
  anyone profiling how `ltree` itself is spending time/memory on a
  given tree; deliberately excluded from `--save-output` snapshots.
- **New:** `-o A` / `-oA` -- turn on every module in one shot instead
  of spelling out the full list; rejected if combined with any other
  module name in the same `-o`, since it's already all of them.
- **Changed:** `CHARS` now counts *visible* characters instead of raw
  UTF-8 codepoints -- combining marks, variation selectors, and
  zero-width joiners no longer inflate the count, and a two-codepoint
  emoji flag counts as the one flag it displays as.
- **New:** the project is now split across `src/*.c` by responsibility
  (scanning, rendering, JSON, hashing, diffing, persistence -- see
  `docs/architecture.md`) instead of one file, now that this many
  independent features sit on top of the original counter.

## What changed in the ls-mode rework

Full design reasoning in [`docs/plan-ls-rework.md`](docs/plan-ls-rework.md).

- **Changed (default behavior):** no-args `ltree` is now a non-recursive
  `[Folders]`/`[Files]` listing of `path` only, like plain `ls`. The old
  recursive connector-tree view is still there, just opt-in now via
  `-o TREE` (which also makes `-L` meaningful again).
- **New:** `-o HIDDEN` -- shows dotfiles/dot-dirs, hidden by default
  now (previously always shown); appended after visible entries within
  each ls-mode block.
- **New:** `-o E,<MODULES>` (`-oE,...`) -- every display module
  *except* the ones listed, the inverse of `-oA`.
- **New:** `-o ...,O` -- render `-o` columns in the order you typed
  them instead of the fixed `L`/`C`/`P`/`S`/`D`/`H` order.
- **New:** `--condense` -- one `[L:x C:y ...]` bracket per entry
  instead of one bracket per active column.
- **New:** `--sort <abc|birth|modified|lines|chars|types>[,combined][,reversed]`
  -- ls-mode only. `types` buckets `[Files]` into per-extension
  `[ext]` sub-headers; `combined` drops the `[Folders]`/`[Files]`
  split entirely.
- **New:** `--live` -- streams `-o TREE`'s output top-down as the walk
  happens instead of buffering the whole tree first, using fixed-width
  columns (a predictable position, not jagged per-block widths) since
  the rest of the tree's shape isn't known yet. Went through two
  earlier drafts first: always-on streaming with no flag at all (too
  aggressive -- lost whole-tree alignment unconditionally), then
  always-on streaming with per-directory-measured alignment (looked
  jagged in practice once actually used) -- fixed-width `--live` as an
  explicit opt-in is what stuck. `-o DIFF` can't mark `--live`-streamed
  lines either way, since diffing needs the complete tree.
- **New:** the default ls-mode listing packs into a real `ls -C`-style
  multi-column grid when writing to a terminal with no `-o` data
  column active (piped output, or any active column, stays
  one-per-line).
- **New:** stdin as path input -- `path` defaults to reading a line
  from stdin when no positional arg was given and stdin isn't a
  terminal.
- **New:** `--stdout exclusive|inclusive <MODULES>` -- forces JSON
  filtered to exclude/keep-only the given modules' fields; never
  affects `--save-output` snapshots, which always stay complete.
- **Changed:** `TOTAL:`/`FILES:` now use the same `[X: value]` bracket
  style as per-entry columns instead of plain `label: value` lines.
- **New:** creation time (`--sort birth`) via `statx()`'s `STATX_BTIME`,
  falling back to mtime when the filesystem/kernel doesn't report one.
- **New:** `include/`/`src/` are now both split into seven subsystem
  subdirectories (`core`, `scan`, `hash`, `render`, `io`, `debug`,
  `util`, plus a new `sort`) instead of one flat directory each, and
  the module list that used to be hand-duplicated between `main.c`'s
  CLI parser and `render_tree.c`'s local rendering code is now one
  shared table (`core/modules.h`/`.c`).
