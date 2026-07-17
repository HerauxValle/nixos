<!-- &desc: "The complete flag-by-flag reference: the ls-mode-vs-tree-mode split (including -o TREE's default whole-tree-aligned buffering, --live's fixed-width streaming, and ls-mode's ls -C grid), every -o module, --condense, --sort, --stdout JSON filtering, exclude/gitignore matching, hashing, diffing, and the debug report." -->

# Usage

```
ltree [path] [options]
```

`path` defaults to `.`; if no positional path is given and stdin isn't
a terminal, `ltree` reads one line from stdin and uses that as the
path instead (so `find . -maxdepth 1 -type d | head -1 | ltree` style
pipelines work). Flags can appear in any order, including before the
path -- `ltree -j /some/path` and `ltree /some/path -j` are the same
call.

## Two views: ls-mode (default) and tree mode (`-o TREE`)

Without `-o TREE`, `ltree` lists only `path`'s **direct children**
(non-recursive, like plain `ls`), grouped into a `[Folders]` block
then a `[Files]` block, each case-insensitive alphabetical by default.
On a terminal, with no `-o` data column active, each block packs into
a real multi-column grid the way bare `ls` does (piped output, or any
active `-o` column, always stays one entry per line -- see
[The ls-style grid](#the-ls-style-grid-ls-mode-only)).

`-o TREE` switches to the classic recursive connector-tree view
instead -- everything about depth/recursion (`-L`) and `--sort` only
applies in that mode, noted at each relevant section below. Buffered
and whole-tree column aligned by default, same as ls-mode; `--live`
streams it top-down as the walk happens instead -- see
[--live streaming](#--live-streaming--o-tree-only).

`-o HIDDEN` shows dotfiles/dot-dirs -- hidden from the walk entirely
by default, in *either* view (this is a scan-level exclusion, not just
a display filter). In ls-mode, hidden entries are appended after the
visible ones within their own `[Folders]`/`[Files]` block; in tree
mode they just sort into their normal alphabetical position.

## Flags

| Flag | Effect |
|---|---|
| `-j` | Output JSON instead of a directory listing. |
| `-d` | List directories only. |
| `-L <n>` (also `-L<n>`) | Max depth to descend, like `tree -L`. Only meaningful with `-o TREE` -- ls-mode is always exactly one level deep. Directories at the cutoff are still shown, marked `(...)`, just not expanded. |
| `-o <MODULES>` | Comma-separated, any order: `LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH,DESC,DIFF,DEBUG,TREE,HIDDEN`. See below. |
| `-oA` | Every module at once. Always alone, no module list. |
| `-oE <MODULES>` | Every module **except** the ones named (`ltree -oE DESC,HASH`). Needs at least one module named -- bare `-oE` alone is a usage error. |
| `-oO [MODULES]` | Renders `-o` columns in the order they were actually typed across the run, instead of the fixed `L`/`C`/`P`/`S`/`D`/`H`/`DESC` order. `MODULES` is optional -- `ltree -oO HASH` both sets typed-order rendering and enables `HASH` in one go; `ltree -oO` alone just sets typed-order rendering. |
| `--exclude <list>` | Comma-separated names/globs to skip. Quote entries containing spaces: `--exclude "build,*.pyc,some dir"`. |
| `--gitignore` | Also exclude whatever the scan root's `.gitignore` would. Composes with `--exclude` -- either list can exclude a path. |
| `--cryptographic` | `-o HASH` / `-o DIFF` use SHA-256 instead of the default xxHash64. |
| `--simple-hash` | `-o HASH`/`-o DIFF` hash a bounded sample instead of the whole file for anything over 128KiB. See [Hashing](#hashing). |
| `--save-output[=DIR]` | Write a JSON snapshot to `DIR/.ltree/` (default: `<path>/.ltree/`). Filename is a local-time `dd-mm-yyyy_hh:mm:ss.json` timestamp. Always complete regardless of `--stdout` filtering on the same run. |
| `--no-colour` (also `--no-color`) | Disable ANSI colour. |
| `--condense` | One `[L:x C:y ...]` bracket per entry instead of one bracket per active column. See [Condensed columns](#condensed-columns). |
| `--live` | `-o TREE` only (warns and is ignored otherwise), no effect with `-j`. Streams top-down as the walk happens instead of waiting for it to finish; fixed-width columns instead of whole-tree-measured ones. See [--live streaming](#--live-streaming--o-tree-only). |
| `--sort <MODES>` | ls-mode only (warns and is ignored with `-o TREE`). See [Sorting](#sorting-ls-mode-only). |
| `--stdout <exclusive\|inclusive> <MODULES>` | Forces JSON output (implies `-j`) filtered to a subset of fields. See [Filtered JSON output](#filtered-json-output---stdout). |
| `--desc <format>` (also `--desc=<format>`) | What `-o DESC` searches file content for. See [DESC](#desc). |
| `-D <format>` | Alias for `--desc` -- **not** `-d`, which is dirs-only. |
| `-h`, `--help` | Show help and exit. |

## The `-o` modules

Each of `LINES` / `CHARS` / `PERMISSIONS` / `SIZE` / `DATE` / `HASH`
prints as its **own** aligned `[X: ...]` bracket per entry, in a fixed
order (`L`, `C`, `P`, `S`, `D`, `H`) regardless of what order you list
them in `-o` -- unless `-oO` is also passed, which switches to
the order you actually typed (see the flags table above). Directories
aggregate `LINES`/`CHARS`/`SIZE` over their **direct** children only
(not the whole subtree at once -- totals accumulate naturally as you
walk up); `PERMISSIONS`/`DATE` are always the entry's own, never
aggregated.

- **`LINES`** -- line count (`memchr`-counted newlines).
- **`CHARS`** -- *visible* character count, not raw UTF-8 codepoint
  count. `ltree` decodes real codepoints (rejecting invalid/overlong
  UTF-8 rather than just counting lead bytes) and then applies two
  corrections on top: combining marks, variation selectors, and
  zero-width joiners never add their own count (they modify the glyph
  before them, they don't add a new one), and a pair of
  regional-indicator codepoints -- an emoji flag -- counts as one
  character, not two. This isn't full Unicode grapheme-cluster
  segmentation (UAX #29) -- that needs a Unicode property database
  this project deliberately doesn't carry -- but it's meaningfully
  closer to "what a human would call one character" than raw codepoint
  counting, for the overwhelming majority of real text.
- **`PERMISSIONS`** -- `[P: -rw-r--r--]`, the same 10-character form
  `ls -l` uses.
- **`SIZE`** -- human-readable size, `[S: 4.5K]` / `[S: 128b]` /
  `[S: 1.2G]`.
- **`DATE`** -- last-modified time, local timezone, `dd-mm-yyyy
  hh:mm:ss`.
- **`EXT`** -- toggles showing file extensions in the tree. **Hidden
  by default** -- `report.md` displays as `report`. This only affects
  the tree/ls/JSON *display name*; extension-keyed data (`FILES:`
  summary, the JSON `by_extension` block, `--sort types`) is
  unaffected either way.
- **`HASH`** -- see [Hashing](#hashing) below.
- **`DESC`** -- see [DESC](#desc) below.
- **`TOTAL`** -- appends a `[dirs: n]   [files: n]   [lines: n]
  [chars: n]` summary line after the listing. Not a per-entry column.
- **`FILES`** -- appends a by-extension `[TYPE: x]   [FILES: n]
  [LINES: n]   [CHARS: n]` breakdown after the listing, one row per
  extension, column-aligned the same way per-entry columns are. Not a
  per-entry column.
- **`DIFF`** -- see [Diffing](#diffing) below.
- **`DEBUG`** -- see [Debug report](#debug-report) below.
- **`TREE`** -- switches from the default ls-mode view to the
  recursive connector-tree view. See
  [Two views](#two-views-ls-mode-default-and-tree-mode--o-tree) above.
- **`HIDDEN`** -- shows dotfiles/dot-dirs, hidden by default. See
  [Two views](#two-views-ls-mode-default-and-tree-mode--o-tree) above.

Unknown `-o` tokens print a warning to stderr and are otherwise
ignored; they don't abort the run.

## Condensed columns

By default every active `-o` column gets its own `[X: ...]` bracket,
padded to that column's own widest value, with a fixed 3-space gap
before the next one:

```
report.md   [L: 26]   [C: 1174]   [P: -rw-r--r--]
```

`--condense` collapses that into a single bracket, still colour-coded
per field, with the space after each field's colon dropped and no
per-field width padding inside the bracket (that's the point -- tight,
not columnar):

```
report.md   [L:26 C:1174 P:-rw-r--r--]
```

The trailing `[m]` `DIFF` modified-flag is unaffected either way --
it's a modification flag, not one of the data columns `--condense`
folds together.

## Sorting (ls-mode only)

`--sort <mode>[,<mode>...]` reorders the ls-mode view. Has no effect
under `-o TREE` (warned and ignored) -- tree mode always keeps plain
case-insensitive alphabetical order.

One **base** mode (mutually exclusive -- passing two is a usage error):

| Mode | Order |
|---|---|
| `abc` (default) | Case-insensitive alphabetical. |
| `birth` | Creation time, oldest first. Via `statx()`'s `STATX_BTIME`; falls back to last-modified time when the filesystem/kernel doesn't report a birth time. |
| `modified` | Last-modified time, oldest first (newest at the bottom). |
| `lines` | Line count, fewest first (most at the bottom). |
| `chars` | Char count, fewest first (most at the bottom). |
| `types` | Buckets the `[Files]` block into per-extension `[ext]` sub-headers, alphabetical by extension, alphabetical within a bucket. `[Folders]` is unaffected -- directories don't have an extension in this project's model. |

Plus two **modifiers**, combinable with any one base mode and with
each other:

- **`combined`** -- don't split into `[Folders]`/`[Files]` at all, one
  flat list sorted by the base mode. Dropped (with a warning) when
  paired with `types`, since `types` already has its own grouping.
- **`reversed`** -- flips whatever ordering the base mode produces.

`--sort` takes over ordering entirely for a group -- the default
"hidden entries appended after visible ones" placement (see
[Two views](#two-views-ls-mode-default-and-tree-mode--o-tree) above)
does **not** layer on top of a `--sort` order; hidden entries sort in
wherever the chosen mode puts them.

## The ls-style grid (ls-mode only)

When stdout is a terminal and no `-o` data column (`LINES`, `CHARS`,
`PERMISSIONS`, `SIZE`, `DATE`, `HASH`) is active, each `[Folders]`/
`[Files]` block (or each `--sort types` `[ext]` bucket, or the single
flat list under `--sort combined`) packs into a real multi-column
grid, the same column-major "fill down, then across" layout bare
`ls` uses: as many columns as fit the terminal width (`ioctl`
`TIOCGWINSZ`, falling back to the `COLUMNS` environment variable, then
80), each column padded to its own widest entry.

Piped output (or output redirected to a file) always stays one entry
per line instead, the same way real `ls` only grids when writing to a
terminal -- and so does any run with an active `-o` data column, since
per-entry brackets and a packed grid don't mix.

## `--live` streaming (`-o TREE` only)

`-o TREE` is buffered by default -- the whole tree is walked first,
then flattened and printed in one pass, whole-tree column aligned,
same convention as every other view. `--live` switches to printing
connector-tree lines the instant each directory's own direct children
are known, instead of waiting for the entire walk to finish -- most
useful on a large or deeply nested tree, where buffer-then-print-once
can leave the terminal blank for a while. No effect combined with
`-j` (warned and ignored) or without `-o TREE` (also warned and
ignored -- ls-mode is already one non-recursive directory, nothing to
stream).

It streams **top-down**: the root directory's own listing prints
first, then each subdirectory's as `ltree` enters it (depth-first
after that, following the same order the walk itself descends in) --
not bottom-up, which is what a naïve print-after-recursing
implementation would give you.

Whole-tree column alignment is impossible while streaming -- the rest
of the tree's shape isn't known yet when a given line prints. Rather
than aligning per-directory-block (jagged: each directory's columns
start at a different position, depending on that directory's own
content), `--live` uses **fixed-width columns and a fixed start
position** instead, so output still lines up predictably across the
whole run:

| Column | Fixed width | Fits |
|---|---|---|
| name start | 44 characters | moderate nesting/name lengths |
| `LINES` | 13 | 8-digit line counts |
| `CHARS` | 15 | 10-digit char counts |
| `PERMISSIONS` | 15 | always this width anyway |
| `SIZE` | 11 | up to `999.9G`-style values |
| `DATE` | 24 | always this width anyway |
| `HASH` | 21 | 16 hex chars |

If an individual value is wider than its column's fixed width (a
9-digit line count, a name long enough to blow past the 44-character
start), that one row's *following* columns simply won't line up with
the rest -- the same kind of overflow any fixed-width table accepts,
not a bug. `TOTAL`/`FILES`/`DEBUG`/the DIFF note still print once, at
the very end, since those need the complete walk regardless of
`--live`.

Diff marking (`-o DIFF`'s red name + trailing `[m]`) never appears in
`--live`-streamed rows, even if `-o DIFF` is also passed -- diffing
compares against the finished tree, which isn't available until after
everything has already streamed.

## Loading spinner

Any scan taking long enough to notice shows an animated spinner --
writes only to **stderr** (never stdout, so `-j`/piped/redirected
output is byte-for-byte unaffected) and only draws anything when
stderr is actually a terminal, so non-interactive runs (scripts, CI,
`tools/smoke_test.sh`) are a no-op by construction. Rate-limited to
about once every 90ms, so a scan finishing faster than that never
draws anything at all -- no flicker on ordinary runs.

- **Without `--live`:** nothing else prints until the whole walk
  finishes, so the spinner is the only thing on screen; it's cleared
  right before the buffered tree/ls/JSON view prints.
- **With `--live`:** every real line streamed to stdout is preceded by
  erasing the spinner and followed by immediately redrawing it, so it
  always stays the bottom-most line through the whole run, then clears
  once before `TOTAL`/`FILES`/`DEBUG`/the DIFF note print at the end.

## Filtered JSON output (`--stdout`)

`--stdout <exclusive|inclusive> <MODULES>` forces JSON output (as if
`-j` were also passed) filtered to a subset of keys/fields. `MODULES`
uses the same names as `-o`, mapped onto JSON keys:

| Module | JSON key/field | Scope |
|---|---|---|
| `TREE` | `"tree"` | top-level -- the whole entry structure |
| `TOTAL` | `"total"` | top-level |
| `FILES` | `"by_extension"` | top-level |
| `DEBUG` | `"debug"` | top-level (only ever present when `-o DEBUG` was also passed) |
| `LINES` | `"lines"` | per-entry |
| `CHARS` | `"chars"` | per-entry |
| `PERMISSIONS` | `"mode"` | per-entry |
| `SIZE` | `"size"` | per-entry |
| `DATE` | `"mtime"` | per-entry |
| `HASH` | `"hash"` | per-entry |
| `DESC` | `"desc"` | per-entry |
| `DIFF` | `"modified"` | per-entry (only present when `-o DIFF` was also passed) |

`"name"`/`"type"`/`"symlink"` per entry and `"path"`/`"generated_at"`/
`"hash_algo"` at the top level are structurally required and never
filterable. `EXT`/`HIDDEN` have no JSON field of their own (`EXT` only
ever affects the tree/ls *display name*, never the JSON, which always
carries full names) -- accepted as `--stdout` module names, just a
no-op.

- **`exclusive <list>`** -- emit everything `-j` normally would,
  except the listed keys/fields.
- **`inclusive <list>`** -- emit **only** the listed keys/fields (plus
  the always-present structural ones). Note per-entry fields need
  `TREE` also listed to have anywhere to appear -- `--stdout inclusive
  LINES` without `TREE` produces a `"tree"`-less document, since
  `LINES` alone never turns the tree structure itself back on.

`--stdout` never affects `--save-output` snapshots on the same run --
a snapshot always writes the complete JSON regardless of what the
terminal output was filtered to, since a filtered snapshot missing
(say) `HASH` would silently break `-o DIFF` on every future run
against it.

Naming a heavy-to-compute module (`HASH`, `DESC`) in a `--stdout`
filter actually computes it, the same as if the matching `-o` had been
passed -- `--stdout inclusive HASH,TREE` produces real hashes even
without `-o HASH`, and `--stdout exclusive HASH` (i.e. *not* excluding
it) does too. Plain `-j` with **no** `--stdout` filter is the one
exception to that: it stays lazy, computing `HASH`/`DESC` only when the
matching `-o` (or `--save-output`) actually asked for them -- this is
the pre-existing, documented "only what was actually asked for"
contract, not something `-j` on its own overrides.

## Column alignment

By default (ls-mode, and `-o TREE` without `--live`) `ltree` does two
passes before printing anything: first it flattens the whole listing
into lines and renders every active module's text (plain, no colour)
to measure that module's own max width, *then* it prints. Two effects
fall out of that:

- Every entry's brackets start at the same column, `8` characters past
  the widest name+prefix in the whole listing (not just the current
  line) -- so nothing shifts around based on how deep an entry is
  nested (`-o TREE`) or how it's indented (ls-mode, `--sort types`'s
  extra nesting under an `[ext]` header).
- Each module column is padded to its own widest value across the
  whole listing, then followed by a fixed 3-space gap before the next
  module's bracket (unless `--condense` is active -- see
  [Condensed columns](#condensed-columns)). A short `[L: 1]` and a
  long `[L: 128]` line up their *closing* brackets, and the next
  module (say `[C: ...]`) starts in the same column on every line.

`--live` is the one exception -- it can't measure the whole tree
before printing, since printing happens *during* the walk. See
[--live streaming](#--live-streaming--o-tree-only) for its fixed-width
columns instead.

This is why enabling more modules costs a wider terminal, not a
messier one -- see the example in the main README for what a
multi-column `-o` output looks like in practice.

## Exclude / gitignore matching

Patterns with no `/` match the basename only (`*.pyc` or
`node_modules` hits at any depth). Patterns containing `/` match the
path relative to the scan root. Matching is `fnmatch()` without
`FNM_PATHNAME`, so a single `*` can cross path separators.

`--gitignore` reads a single `.gitignore` at the scan root and applies
a documented *subset* of real gitignore semantics:

- Comments (`#`) and blank lines are skipped.
- A trailing `/` means "directories only".
- A leading `/` anchors the pattern to the scan root; otherwise it
  matches the basename at any depth (same convention as `--exclude`).
- A leading `!` re-includes a path an earlier pattern excluded --
  patterns are applied in file order, **last match wins**, exactly
  like real gitignore.
- Nested `.gitignore` files (one per subdirectory) are **not** read;
  only the scan root's `.gitignore` applies.

`--exclude` and `--gitignore` compose: either list can exclude a
path, and enabling one doesn't disable the other.

`.ltree` (the tool's own snapshot directory, see
[Diffing](#diffing)) is **always** hidden from the walk, the same way
most tools hide `.git` -- there's no flag to turn this off, since
scanning your own past snapshots as if they were project content
would make totals and `DIFF` drift on every run. This is unconditional,
separate from (and unaffected by) `-o HIDDEN`.

## Hashing

`-o HASH` and `-o DIFF` need a per-file/per-directory digest. Two
algorithms are implemented from scratch (no external dependency):

- **Default: xxHash64** (`HASH_ALGO_FAST`) -- an 8-byte digest,
  non-cryptographic, chosen for raw throughput. For change detection
  you want speed, and a 64-bit digest is already astronomically
  collision-safe for "did this file change" purposes.
- **`--cryptographic`: SHA-256** (`HASH_ALGO_CRYPTO`) -- a 32-byte
  digest, collision-resistant, for anyone who wants to actually trust
  the hash for integrity rather than just drift detection.

A directory's hash is the combined hash of its *direct* children's
`name + hash` pairs, in sorted order -- so a directory's digest
changes if and only if a child is added, removed, renamed, or its own
hash changes. No file is ever re-read to compute a directory hash.

The terminal `[H: ...]` column shows the first 8 bytes of whichever
digest was computed (hex-encoded), even for SHA-256 -- full digests
are only carried in the JSON output, where truncating would defeat
the point.

If `-o HASH` is requested but a file/directory has no digest (this
shouldn't happen in practice, but hashing is skipped for symlinks and
zero-byte files), the column reads `[H: -]`.

### `--simple-hash`

Files `<= 128KiB` are always hashed whole (sampling wouldn't save
anything at that size). Above that, `--simple-hash` hashes a small
fixed buffer -- `[size as 8 bytes][first 64KiB][last 64KiB]` -- through
the exact same `hash_compute()` dispatch, instead of the whole file.
Works unchanged for both xxHash64 and `--cryptographic`'s SHA-256. The
file is already `mmap`'d either way, so only the touched head/tail
pages ever actually get read off disk -- the real I/O saving on large
files, on top of not running the hash's compression function over the
whole thing.

Trade-off: a change confined entirely to a large file's untouched
middle won't be detected. `--save-output`/`-o DIFF` snapshots record
whether the run used it, as a top-level `"hash_sampled"` boolean (see
[`docs/json-schema.md`](json-schema.md)) -- `-o DIFF` always forces its
own run's `--simple-hash` setting to match whatever the snapshot being
compared against used, the same way it already forces the hash
*algorithm* to match (see [Diffing](#diffing) below); otherwise a full
hash compared against a sampled one would flag every large file as
modified regardless of whether it actually changed.

## DESC

`-o DESC` searches each file's content for a marker and prints the
text found between two delimiters as its own `[DESC: ...]` column (or
`[DESC: -]` when nothing matches), and as a `"desc"` JSON field
(string or `null`) when requested via `-o DESC -j` / `--save-output` /
a `--stdout` filter naming `DESC`.

What it searches for is controlled by `--desc <format>` (alias `-D`,
**not** `-d`, which is dirs-only), split once on the literal substring
`"..."`:

- Everything **before** `"..."` is the literal prefix `ltree` searches
  for in the file's bytes.
- Everything **after** `"..."` is the literal closing delimiter it then
  reads up to; the text in between is the description.

The default, `&desc: "..."`, matches this project's own header-comment
convention (see the top of any `.c`/`.h` file in this repo) -- it
searches for `&desc: "` and reads up to the next `"`. A custom
`--desc "&description: *...*"` instead searches for `&description: *`
and reads up to the next `*`. No special-casing of "the character
touching the dots" is needed beyond the plain split -- whatever
immediately precedes/follows `"..."` in the format naturally becomes
the boundary. A format missing `"..."`, or with nothing before/after
it, is a usage error (empty prefix would match everywhere; empty
suffix would capture nothing every time).

The search is bounded for performance: only the first 64KiB of a file
is searched for the prefix (this project's own `&desc:` comments
always sit at the top), and the closing delimiter is only looked for
within 4096 bytes after a prefix match -- past that, it's treated as
no match rather than scanning arbitrarily far into a large file. Only
the first match is used.

## Diffing

`-o DIFF` finds the newest `*.json` snapshot under `.ltree/` (see
`--save-output` below), loads it, and marks every entry that differs
from the snapshot: the tree, dir, or file's own name turns red and a
trailing `[m]` (for "modified") appears after that entry's columns.
An entry counts as modified if:

- its type changed (file &lt;-&gt; directory), or
- both sides have a hash of the same length and the hashes differ, or
- (fallback, when a comparable hash isn't available on both sides)
  its size or modification time differs.

Comparison **always uses whichever hash algorithm produced the
snapshot being compared against** (recorded in its `hash_algo`
field), regardless of whether `--cryptographic` was passed on the
current run -- see [`docs/plan.md`](plan.md) for the reasoning. This
means the current scan is hashed with the *snapshot's* algorithm
whenever `-o DIFF` finds one, not necessarily the one you asked for.
Same for `--simple-hash` (recorded as `"hash_sampled"`) -- see
[`--simple-hash`](#--simple-hash) above.

If no previous snapshot exists, the listing prints normally and a
non-blocking note appears at the end, after `TOTAL`/`DEBUG` -- always
last:

```
note: no previous .ltree snapshot found, run again after --save-output to enable DIFF
```

Entries added since the snapshot (no match found by path) are shown
normally, not flagged -- `DIFF` only marks entries it found *and*
determined differ; it doesn't currently distinguish "new" from
"unchanged, no comparable snapshot entry".

Diff marking never appears in `--live`-streamed rows -- see
[--live streaming](#--live-streaming--o-tree-only) above.

## Debug report

`-o DEBUG` appends a hyper-detailed "how did this run go" report,
computed once into a plain struct and rendered either as text or as
JSON, following the same "compute once, format twice" convention as
every other module (see [`docs/json-schema.md`](json-schema.md)).

In the listing view it prints as a `DEBUG:` block, positioned right
after `TOTAL:` (if both are requested) and before the trailing "no
previous snapshot" `DIFF` note, if that also applies:

```
DEBUG:
  -- timing --
  wall clock:              0.000 s
  scan (walk+hash) time:   0.000 s
  cpu user / system:       0.002 s / 0.000 s
  throughput:              34995 files/sec (28.6 us/file avg)
  -- memory --
  peak RSS:                1808 KB
  heap in use / free:      2128 B / 133040 B
  heap arena / mmap'd:     135168 B / 0 B
  tree footprint (est.):   637 B across 4 nodes
  -- OS scheduling / IO --
  page faults (min/maj):   68 / 0
  block IO (in/out):       0 / 0
  ctx switches (vol/inv):  0 / 1
  -- misc --
  dirs / files scanned:    1 / 2
  hash algo:               none
  pid:                     814
  page size:               4096 B
```

In `-j` output the same numbers appear as a `"debug"` object,
directly after `"total"`:

```jsonc
"debug": {
  "wall_clock_seconds": 6.8e-05,   // process start -> just before output
  "scan_seconds": 5e-05,           // build_tree() walk only
  "cpu_user_seconds": 0.001489,
  "cpu_system_seconds": 0.0,
  "peak_rss_kb": 1692,
  "minor_page_faults": 88,
  "major_page_faults": 0,
  "block_input_ops": 0,
  "block_output_ops": 0,
  "voluntary_ctx_switches": 0,
  "involuntary_ctx_switches": 0,
  "heap_in_use_bytes": 2128,       // mallinfo2 uordblks
  "heap_free_bytes": 133040,       // mallinfo2 fordblks
  "heap_mmap_bytes": 0,            // mallinfo2 hblkhd
  "heap_arena_bytes": 135168,      // mallinfo2 arena
  "dirs_scanned": 1,
  "files_scanned": 2,
  "nodes_total": 4,
  "tree_memory_bytes_estimate": 637, // Node structs + names + child arrays
  "files_per_second": 39656.57,
  "avg_us_per_file": 25.22,
  "hash_algo": "none",
  "pid": 815,
  "page_size_bytes": 4096
}
```

The `debug` key is only present at all when `-o DEBUG` was actually
requested -- unlike `total`/`by_extension`, which are always in the
JSON regardless of `-o` flags (both still subject to `--stdout`
filtering), `debug` follows the same opt-in gating as the listing
view's `DEBUG:` block, since collecting and printing this much detail
by default would just be noise for anyone not asking for it.

`--save-output` snapshots **never** include a `debug` block, even if
`-o DEBUG` was passed on that run -- the numbers are ephemeral
per-run measurements (wall clock, RSS, page faults), not something
that should ever be compared against by `-o DIFF` or bloat a
snapshot meant to represent the tree's own content.

## Saving snapshots

`--save-output[=DIR]` writes the same JSON that `-j` would print,
**always complete regardless of any `--stdout` filtering on the same
run** (see [Filtered JSON output](#filtered-json-output---stdout)
above), to `<DIR or path>/.ltree/dd-mm-yyyy_hh:mm:ss.json` (local
time), creating the `.ltree` directory if needed. This is what
`-o DIFF` compares against on a later run. Saving is non-fatal on
failure (a warning goes to stderr; the rest of the run still completes
and still exits `0`).
