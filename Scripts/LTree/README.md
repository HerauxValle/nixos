# LTree

A `tree` replacement that counts lines and characters per file/dir,
shows permissions/size/last-modified, hashes and diffs a directory
against its last scan, does it fast (mmap + memchr, single filesystem
walk), and can dump the same information as JSON instead of a
pretty-printed tree.

Zero external dependencies -- straight libc + POSIX (`dirent`,
`mmap`, `fnmatch`). Builds the same everywhere with just a C
compiler; the Nix flake exists for reproducibility, not because it
needs anything exotic.

```
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
  dirs:  4
  files: 6
  lines: 10
  chars: 312

FILES:
  TYPE       FILES       LINES       CHARS
  c              1           3          24
  py             1           2          18
  txt            1           2          24
  bin            1           1         234
  md             1           1           6
```

## Build

Plain gcc:

```sh
gcc -O3 -std=c11 -Wall -Wextra -o ltree src/*.c
```

Or via the flake:

```sh
nix build .#default        # -> result/bin/ltree
nix develop                 # gcc + gdb + valgrind for hacking on it
```

## Usage

```
ltree [path] [options]

  -j                    output JSON instead of a tree view
  -d                    list directories only
  -L <n>                max depth to descend (like tree -L), also -L<n>
  -o <MODULES>          comma-separated, any order:
                          LINES, CHARS, TOTAL, FILES,
                          PERMISSIONS, SIZE, DATE, EXT, HASH, DIFF, DEBUG
  -o A                  every module at once (also -oA). Can't be combined
                        with other module names -- it's already all of them.
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
  -h, --help            this help
```

`path` defaults to `.`. Flags can appear in any order, including
before the path.

`LINES`/`CHARS`/`PERMISSIONS`/`SIZE`/`DATE`/`HASH` each print as their
own aligned `[X: ...]` column per entry, in a fixed order regardless
of the order you list them in `-o` (dirs aggregate
`LINES`/`CHARS`/`SIZE` over their direct children; `PERMISSIONS`/
`DATE` are always the entry's own). `EXT` toggles showing file
extensions in the tree (hidden by default -- `report.md` shows as
`report`). `CHARS` counts *visible* characters, not raw codepoints --
combining marks, variation selectors, and zero-width joiners don't
add their own count, and an emoji flag (two regional-indicator
codepoints) counts as one, not two. `DIFF` compares against the
newest `.ltree` snapshot, marking changed entries red with a trailing
`[m]`. `TOTAL`, `FILES`, and `DEBUG` are summary sections appended at
the end, not per-entry columns. `DEBUG` prints a hyper-detailed run
report -- timing, peak RSS, heap stats, page faults, throughput --
right after `TOTAL` (and, in `-j` output, as a `"debug"` object); it's
never written into `--save-output` snapshots, since it's ephemeral
run-to-run noise that would only pollute diffing. `-o A` (or `-oA`)
turns on every module at once and can't be combined with anything
else in the same list.

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
# just the tree, no extra columns
ltree

# lines + chars + a totals summary
ltree -o LINES,CHARS,TOTAL

# full metadata columns, gitignore-aware, two levels deep
ltree --gitignore -L2 -o LINES,PERMISSIONS,SIZE,DATE

# take a snapshot now, keep working, then see what changed
ltree --save-output
# ... edit some files ...
ltree -o DIFF,LINES

# JSON, with cryptographic hashes, piped elsewhere
ltree -j -o HASH --cryptographic

# hyper-detailed run report: timing, peak RSS, heap, page faults
ltree -o DEBUG

# everything at once
ltree -oA
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
