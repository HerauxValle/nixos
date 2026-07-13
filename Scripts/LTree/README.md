# LTree

A `tree` replacement that also counts lines and characters per file/dir,
does it fast (mmap + memchr, single filesystem walk), and can dump the
same information as JSON instead of a pretty-printed tree.

Zero external dependencies -- straight libc + POSIX (`dirent`, `mmap`,
`fnmatch`). Builds the same everywhere with just a C compiler; the Nix
flake exists for reproducibility, not because it needs anything exotic.

```
testtree
├── docs/                       [L: 1, C: 20]
│   ╰── README.md               [L: 1, C: 20]
╰── src/                        [L: 9, C: 431]
    ├── a.c                     [L: 3, C: 18]
    ├── sub1/                   [L: 2, C: 371]
    │   ├── b.py                [L: 1, C: 14]
    │   ╰── blob.bin            [L: 1, C: 357]
    ╰── sub2/                   [L: 2, C: 34]
        ╰── utf8.txt            [L: 2, C: 34]

TOTAL:
  dirs:  3
  files: 4
  lines: 11
  chars: 443
```

## Build

Plain gcc:

```sh
gcc -O3 -std=c11 -Wall -Wextra -o ltree src/ltree.c
```

Or via the flake:

```sh
nix build .#default        # -> result/bin/ltree
nix develop                 # gcc + gdb + valgrind for hacking on it
```

## Usage

```
ltree [path] [options]

  -j                  output JSON instead of a tree view
  -d                  list directories only
  -L <n>              max depth to descend (like tree -L), also -L<n>
  -o <MODULES>        comma-separated: LINES,CHARS,TOTAL,FILES (any order)
  --exclude <list>    comma-separated names/globs to skip, quote entries
                      with spaces: --exclude "build,*.pyc,some dir"
  --no-colour         disable ANSI colour (also --no-color)
  -h, --help          this help
```

`path` defaults to `.`. Flags can appear in any order, including before
the path -- `ltree -j /some/path` and `ltree /some/path -j` are the
same call.

See `docs/` for the full breakdown of each flag, the exclude-pattern
matching rules, the column-alignment logic, and the JSON schema.

## What changed from the old `countlines.py`

- C instead of Python: one mmap + one `memchr` scan per file instead of
  a Python-level decode; ~1s to walk and count 6000 files / 90MB of
  text under `/usr/include`.
- The tree drawing is a real tree algorithm now (tracks last-child per
  directory) instead of always assuming another sibling is coming --
  branches close off with a rounded corner (`╰──`) instead of just
  trailing away.
- `LINES`/`CHARS`/`TOTAL`/`FILES` are now opt-in via `-o`, and when
  requested, columns line up in a straight edge across the *whole*
  tree, not just the current line.
- Native JSON output (`-j`) carries the same tree, so it's easy to feed
  into something else without scraping the pretty-printed text.
- `--exclude` with comma-separated glob patterns, `-d` for dirs-only,
  and depth limiting via `-L`.
