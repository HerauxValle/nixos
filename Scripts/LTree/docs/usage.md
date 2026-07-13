# Usage

```
ltree [path] [options]
```

`path` defaults to `.`. Flags can appear in any order, including
before the path -- `ltree -j /some/path` and `ltree /some/path -j`
are the same call.

## Flags

| Flag | Effect |
|---|---|
| `-j` | Output JSON instead of a tree view. |
| `-d` | List directories only. |
| `-L <n>` (also `-L<n>`) | Max depth to descend, like `tree -L`. Directories at the cutoff are still shown, marked `(...)`, just not expanded. |
| `-o <MODULES>` | Comma-separated, any order: `LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH,DIFF,DEBUG`. See below. |
| `-o A` (also `-oA`) | Every module at once. Can't be combined with any other module name in the same list -- `ltree` rejects `-o A,DEBUG` rather than silently ignoring the redundant token. |
| `--exclude <list>` | Comma-separated names/globs to skip. Quote entries containing spaces: `--exclude "build,*.pyc,some dir"`. |
| `--gitignore` | Also exclude whatever the scan root's `.gitignore` would. Composes with `--exclude` -- either list can exclude a path. |
| `--cryptographic` | `-o HASH` / `-o DIFF` use SHA-256 instead of the default xxHash64. |
| `--save-output[=DIR]` | Write a JSON snapshot to `DIR/.ltree/` (default: `<path>/.ltree/`). Filename is a local-time `dd-mm-yyyy_hh:mm:ss.json` timestamp. |
| `--no-colour` (also `--no-color`) | Disable ANSI colour. |
| `-h`, `--help` | Show help and exit. |

## The `-o` modules

Each of `LINES` / `CHARS` / `PERMISSIONS` / `SIZE` / `DATE` / `HASH`
prints as its **own** aligned `[X: ...]` bracket per entry, in a fixed
order (`L`, `C`, `P`, `S`, `D`, `H`) regardless of what order you list
them in `-o` -- so output is stable across runs even if you type the
list differently. Directories aggregate `LINES`/`CHARS`/`SIZE` over
their **direct** children only (not the whole subtree at once --
totals accumulate naturally as you walk up); `PERMISSIONS`/`DATE` are
always the entry's own, never aggregated.

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
  the tree/JSON *display name*; extension-keyed data (`FILES:`
  summary, the JSON `by_extension` block) is unaffected either way.
- **`HASH`** -- see [Hashing](#hashing) below.
- **`TOTAL`** -- appends a summary block (dirs/files/lines/chars)
  after the tree. Not a per-entry column.
- **`FILES`** -- appends a by-extension breakdown (files/lines/chars
  per extension) after the tree. Not a per-entry column.
- **`DIFF`** -- see [Diffing](#diffing) below.
- **`DEBUG`** -- see [Debug report](#debug-report) below.

Unknown `-o` tokens print a warning to stderr and are otherwise
ignored; they don't abort the run.

## Column alignment

`ltree` does two passes before printing anything: first it flattens
the whole tree into lines and renders every active module's text
(plain, no colour) to measure that module's own max width, *then* it
prints. Two effects fall out of that:

- Every entry's brackets start at the same column, `8` characters past
  the widest name+prefix in the whole tree (not just the current
  line) -- so nothing shifts around based on how deep an entry is
  nested.
- Each module column is padded to its own widest value across the
  whole tree, then followed by a fixed 3-space gap before the next
  module's bracket. A short `[L: 1]` and a long `[L: 128]` line up
  their *closing* brackets, and the next module (say `[C: ...]`)
  starts in the same column on every line.

This is why enabling more modules costs a wider terminal, not a
messier one -- see the example in the main README for what the full
`-o LINES,CHARS,PERMISSIONS,SIZE,DATE` output looks like in practice.

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
would make totals and `DIFF` drift on every run.

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

If no previous snapshot exists, the tree prints normally and a
non-blocking note appears at the end:

```
note: no previous .ltree snapshot found, run again after --save-output to enable DIFF
```

Entries added since the snapshot (no match found by path) are shown
normally, not flagged -- `DIFF` only marks entries it found *and*
determined differ; it doesn't currently distinguish "new" from
"unchanged, no comparable snapshot entry".

## Debug report

`-o DEBUG` appends a hyper-detailed "how did this run go" report,
computed once into a plain struct and rendered either as text or as
JSON, following the same "compute once, format twice" convention as
every other module (see [`docs/json-schema.md`](json-schema.md)).

In the tree view it prints as a `DEBUG:` block, positioned right
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
JSON regardless of `-o` flags, `debug` follows the same opt-in
gating as the tree view's `DEBUG:` block, since collecting and
printing this much detail by default would just be noise for anyone
not asking for it.

`--save-output` snapshots **never** include a `debug` block, even if
`-o DEBUG` was passed on that run -- the numbers are ephemeral
per-run measurements (wall clock, RSS, page faults), not something
that should ever be compared against by `-o DIFF` or bloat a
snapshot meant to represent the tree's own content.

## Saving snapshots

`--save-output[=DIR]` writes the same JSON that `-j` would print to
`<DIR or path>/.ltree/dd-mm-yyyy_hh:mm:ss.json` (local time),
creating the `.ltree` directory if needed. This is what `-o DIFF`
compares against on a later run. Saving is non-fatal on failure (a
warning goes to stderr; the rest of the run still completes and still
exits `0`).
