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
| `-o <MODULES>` | Comma-separated, any order: `LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH,DIFF`. See below. |
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
- **`CHARS`** -- UTF-8 codepoint count (not byte count).
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

## Saving snapshots

`--save-output[=DIR]` writes the same JSON that `-j` would print to
`<DIR or path>/.ltree/dd-mm-yyyy_hh:mm:ss.json` (local time),
creating the `.ltree` directory if needed. This is what `-o DIFF`
compares against on a later run. Saving is non-fatal on failure (a
warning goes to stderr; the rest of the run still completes and still
exits `0`).
