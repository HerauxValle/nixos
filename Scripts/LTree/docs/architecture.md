# Architecture

## One walk, many views

`build_tree()` walks the filesystem exactly once with `opendir`/`readdir`,
producing an in-memory `Node` tree: every directory node knows its
direct children, every file node knows its own line/char count. All
the output modes -- the aligned tree view, the `TOTAL` summary, the
`FILES`-by-extension summary, and `-j` JSON -- read that same tree
afterwards. The expensive part (stat + mmap + byte scanning) happens
once, not once per requested `-o` module.

```
main()
  build_tree(root, path, depth=0, ...)   -- single recursive walk
    for each dirent:
      lstat/stat, exclude check
      if dir:   recurse (unless -L limit or symlink), sum direct children's L/C
      if file:  count_file() via mmap, tally into ExtTable + Totals
    qsort() siblings (dirs and files interleaved, case-insensitive)
  -> Node tree, Totals, ExtTable all fully populated

if -j:     print_json(root, ...)          -- one pass over the tree
else:      flatten(root) -> LineBuf       -- depth-first, tracks is_last
           compute max column width across ALL lines
           print each line padded to that width
           if -o FILES: print_files_summary(ExtTable)
```

## Why mmap + memchr for counting

`count_file()` maps the whole file with `mmap(MAP_PRIVATE)` and does
two linear passes:

1. `memchr()` in a loop to find `'\n'` bytes and count lines. glibc's
   `memchr` is typically vectorized, which beats a hand-written byte
   loop for anything but tiny files.
2. A single byte-scan counting UTF-8 *lead* bytes (any byte that isn't
   a `10xxxxxx` continuation byte) to get a character count that
   matches what `len(text)` would give you in Python over decoded
   UTF-8, without needing a full UTF-8 decoder.

No buffering, no per-line `fgets` overhead, no allocation proportional
to file size beyond the mapping itself. Files that can't be mapped
(empty, zero-length, non-regular) short-circuit to `0, 0`.

## Tree drawing: real last-child tracking

The old Python version always emitted `├── ` and just hoped the
vertical bars below it kept making sense -- it never actually knew
whether a given entry was the last child of its parent. `flatten()`
fixes that directly: children are sorted first, so by the time we
visit entry `i` of `n`, we already know `is_last = (i == n - 1)`. That
one boolean threads through the whole recursion and decides:

- the connector for *this* entry: `╰── ` (rounded corner, U+2570) if
  last, `├── ` otherwise -- there's no rounded T-junction in the box
  drawing block, so only the closing corner rounds off,
- the prefix *inherited by this entry's children*: four spaces if this
  entry was last (nothing needs to keep hanging below it), or `│   `
  if not (a sibling is still coming, so the vertical bar has to keep
  going down past this whole subtree).

## Column alignment

`flatten()` also records, per line, the UTF-8 display width of
`prefix + name` (directories get a synthetic `+1` for the trailing
`/` that gets printed later, so the width matches what's actually on
screen). After the full tree is flattened, we take the max width
across every line (and the root path itself), add 8, and that's where
every `[L: n]`/`[C: n]` column starts, padded with spaces on the
second pass. Two passes are required because the alignment target
depends on the *widest* line in the whole tree, which you can't know
until you've seen all of them -- this is also why JSON and the tree
view both build the full `Node` tree up front rather than streaming
output as they walk.

## Exclusion matching

`--exclude` takes a comma-separated list, quote an entry in `"..."` if
it contains spaces (or a literal comma). Each pattern is checked with
libc's `fnmatch()`:

- no `/` in the pattern -> matched against the **basename** only, so
  `*.pyc` or `node_modules` hits at any depth,
- pattern contains `/` -> matched against the path **relative to the
  scan root**.

`fnmatch()` is called without `FNM_PATHNAME`, so a bare `*` is allowed
to cross `/` -- that already gives you gitignore's `**` behaviour for
free without hand-rolling a second glob engine just for the two-star
case.

## Symlinks

Symlinks are shown (with their own colour) but never descended into,
even if they point at a directory -- that's the simplest cycle-safe
rule available and avoids needing a visited-inode set. A dangling
symlink degrades to showing the link itself with no size info rather
than crashing.

## Memory

Every allocation has a matching free: `node_free()` walks the tree
recursively freeing names and child arrays, `ExtTable`/`LineBuf`/`SBuf`
each own exactly the memory they grew, and `main()` frees the exclude
list and path string before returning. Verified with
`valgrind --leak-check=full` across tree mode, JSON mode, `-d`, `-L`,
and `--exclude` runs: 0 leaks, 0 errors in all of them.
