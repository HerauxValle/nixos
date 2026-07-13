# Usage reference

```
ltree [path] [options]
```

`path` defaults to `.`. All flags work regardless of position relative
to the path or each other.

## `-j` -- JSON output

Switches the whole program to emit a single JSON document instead of
the tree view (and the `FILES` summary, if you had `-o FILES` set --
JSON always includes totals and per-extension stats regardless of
`-o`, since JSON is meant to be the complete raw data, not a filtered
view). Position doesn't matter: `ltree -j some/path` and
`ltree some/path -j` are identical. See `docs/json-format.md` for the
schema.

## `-d` -- directories only

Files are skipped entirely, including for counting -- when `-d` is
set, `TOTAL`'s `files`/`lines`/`chars` and the `FILES` summary will be
empty/zero, since nothing was read. This is also the fastest mode,
since no file content is ever mmap'd.

## `-L <n>` -- max depth

Both `-L 3` and `-L3` work. Matches the semantics of `tree -L`: `-L 1`
shows the given path's immediate children (files and directories) but
does not expand any of those directories further -- they're still
listed, just followed by `(...)` to mark that their contents exist but
weren't shown. Omit `-L` for unlimited depth.

## `-o <MODULES>` -- opt-in columns and summaries

Comma-separated, order doesn't matter, case-insensitive:

- `LINES` -- adds an `[L: n]` field per entry. For a file, `n` is that
  file's own line count. For a directory, `n` is the sum of its
  **direct** children only (not recursive).
- `CHARS` -- same idea, `[C: n]`, character count (UTF-8 codepoints,
  not bytes).
- `TOTAL` -- appends a summary block after the tree: total
  directories, files, lines, chars across everything shown.
- `FILES` -- appends a per-extension breakdown (file count, lines,
  chars), sorted by line count descending, extensionless files grouped
  under `(no ext)`.

`LINES` and `CHARS` render as one combined field per line, e.g.
`[L: 40, C: 1200]`, right-aligned starting 8 spaces past whichever
line in the entire tree has the longest name+indent -- so the columns
form a single straight edge down the page, not a ragged one hugging
each individual filename.

`TOTAL` and `FILES` are summary sections, not per-line columns; they
print once, after the whole tree.

Examples:

```sh
ltree -o LINES                 # just line counts
ltree -o LINES,CHARS           # both, aligned together
ltree -o TOTAL,FILES           # tree view + both summaries, no per-line columns
ltree -o LINES,CHARS,TOTAL,FILES
```

## `--exclude <list>` -- skip names or globs

Comma-separated, no spaces around commas. Wrap an individual entry in
double quotes if it needs to contain a space (or a comma):

```sh
ltree --exclude "node_modules,*.pyc,build"
ltree --exclude "some folder with spaces,*.log"
```

Matching rules:

- an entry with no `/` matches against the **basename** at any depth
  (`*.pyc` hits every `.pyc` file anywhere under `path`),
  and
- an entry containing `/` matches against the path **relative to the
  scanned root** (`src/generated` only excludes that exact relative
  path, not any directory named `generated`).

Standard glob wildcards apply (`*`, `?`, `[...]`) via libc `fnmatch`.
A bare `*` is allowed to cross directory separators, so it already
behaves like gitignore's `**` for the common "match at any depth"
case -- you don't need to write `**` explicitly, though writing it is
harmless (it's treated the same as a single `*`).

## `--no-colour` / `--no-color`

Disables all ANSI colour codes. Colour is **on** by default:
directories bold blue, symlinks bold magenta, branch glyphs dim grey,
`L:` green, `C:` yellow, `TOTAL`/`FILES` headers bold cyan, extension
names in the `FILES` table magenta.

## Exit codes

`0` on success, `1` if the given path doesn't exist or isn't a
directory, or an unrecognised flag was passed.
