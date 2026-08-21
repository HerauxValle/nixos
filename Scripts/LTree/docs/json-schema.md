<!-- &desc: "Documents the exact JSON object shape shared by -j and --save-output (top-level path/total/by_extension/debug/tree keys and the recursive per-entry node shape), including which fields are always present versus gated by -o DEBUG or -o DIFF." -->

# JSON schema

Both `-j` (printed to stdout) and `--save-output` (written to
`.ltree/dd-mm-yyyy_hh:mm:ss.json`) emit exactly the same shape, via
the same writer (`json_render` in `json.c`) -- they can never drift
apart from each other.

## Top level

```jsonc
{
  "path": "testtree",                 // the scanned path, as given on the command line
  "generated_at": "13-07-2026 21:34:37", // local time, "dd-mm-yyyy hh:mm:ss"
  "hash_algo": "xxhash64",            // "xxhash64" | "sha256" | "none"
  "hash_sampled": false,               // true if this run used --simple-hash
  "total": {
    "dirs": 4,
    "files": 6,
    "lines": 10,
    "chars": 312
  },
  "debug": { /* only present when -o DEBUG was requested -- see below */ },
  "by_extension": [
    { "ext": "c", "files": 1, "lines": 3, "chars": 24 }
    // sorted by lines descending, ties broken alphabetically by ext;
    // extensionless files use "ext": "(no ext)"
  ],
  "tree": { /* the root node, see below */ }
}
```

`hash_algo` is `"none"` whenever nothing in the run actually needed a
digest (no `-o HASH`, `-o DIFF`, `--save-output`, or a `--stdout
exclusive|inclusive` filter that resolves to wanting `HASH` -- e.g.
`--stdout inclusive HASH` computes it even without `-o HASH`) -- hashing
is otherwise skipped entirely, not just hidden from output.

`hash_sampled` is always present (like `hash_algo`), never gated by
`--stdout` -- a later `-o DIFF` run reads it (`diff_peek_algo()` in
`io/diff.c`) to force its own `--simple-hash` setting to match the
snapshot's, the same way it already forces the hash algorithm to
match; comparing a full hash against a sampled one would otherwise
flag every large file as modified regardless of whether it actually
changed. See [`docs/usage.md`](usage.md#--simple-hash).

`by_extension` is always present, even for `-j` calls that didn't
request `-o FILES` -- unlike the terminal view, the JSON output isn't
gated by which `-o` modules were passed; it always carries everything
`ltree` computed during the scan. `-o EXT`/`-o HASH` etc. only affect
what the *tree view* prints, not what the JSON contains.

**`debug` is the one exception to that rule.** It's only present when
`-o DEBUG` was passed -- gated the same way the tree view's `DEBUG:`
block is, rather than always-on like `total`/`by_extension` -- since
it's a comparatively heavy, opt-in diagnostic block:

```jsonc
"debug": {
  "wall_clock_seconds": 6.8e-05,     // process start -> just before output
  "scan_seconds": 5e-05,             // build_tree() walk only
  "cpu_user_seconds": 0.001489,
  "cpu_system_seconds": 0.0,
  "peak_rss_kb": 1692,               // getrusage ru_maxrss
  "minor_page_faults": 88,
  "major_page_faults": 0,
  "block_input_ops": 0,
  "block_output_ops": 0,
  "voluntary_ctx_switches": 0,
  "involuntary_ctx_switches": 0,
  "heap_in_use_bytes": 2128,         // mallinfo2 uordblks
  "heap_free_bytes": 133040,         // mallinfo2 fordblks
  "heap_mmap_bytes": 0,              // mallinfo2 hblkhd
  "heap_arena_bytes": 135168,        // mallinfo2 arena
  "dirs_scanned": 1,
  "files_scanned": 2,
  "nodes_total": 4,
  "tree_memory_bytes_estimate": 637, // Node structs + names + child arrays
  "files_per_second": 39656.57,
  "avg_us_per_file": 25.22,
  "hash_algo": "none",               // whichever algo this run actually used
  "pid": 815,
  "page_size_bytes": 4096
}
```

It is also never written by `--save-output`, regardless of whether
`-o DEBUG` was passed on that run -- `save.c` always calls
`json_render()` with a `NULL` debug pointer, since these numbers are
per-run measurements with nothing to do with the tree's own content,
and would just add noise for `-o DIFF` to ignore on every future
comparison. See [`docs/usage.md`](usage.md#debug-report) for the
tree-view rendering and full field list.

## Node object (recursive)

```jsonc
{
  "name": "a.c",                // basename, not full path
  "type": "file",                // "file" | "dir"
  "symlink": false,
  "lines": 3,                    // file: own count. dir: sum of DIRECT children
  "chars": 24,
  "mode": "-rw-r--r--",          // 10-char ls-style permission string
  "size": 24,                    // bytes. file: st_size. dir: sum of DIRECT children
  "mtime": 1783978477,           // Unix epoch seconds, own mtime -- never aggregated
  "hash": "f50bbd2a8ebb44c9",    // hex-encoded digest, or null if not computed
  "desc": "hello world",         // -o DESC marker text, or null if none/not requested
  "modified": false,             // only present when -o DIFF was requested AND
                                  // a matching entry was found in the snapshot
  "truncated": true,             // dirs only, only present when true (hit -L cutoff)
  "children": []                 // dirs only: array of Node objects
}
```

Field notes:

- **`hash`** is the *full* digest (8 bytes/16 hex chars for xxHash64,
  32 bytes/64 hex chars for SHA-256) -- unlike the terminal `[H: ...]`
  column, which always truncates to 8 bytes for display. `null` when
  hashing wasn't requested for this run.
- **`desc`** is the full, untruncated marker text found by `-o DESC` /
  `--desc`/`-D` (see [`docs/usage.md`](usage.md#desc)) -- unlike the
  terminal `[DESC: ...]` column, which caps display at 480 characters.
  `null` when `DESC` wasn't requested for this run, or no marker
  matched within the search bounds.
- **`modified`** is omitted entirely (not `false`) unless `-o DIFF`
  was passed *and* this entry was matched against the loaded
  snapshot by path. An entry with no `modified` key means DIFF either
  wasn't requested, or found no prior snapshot to compare this entry
  against (e.g. it's new since the snapshot was taken).
- **`truncated`** is omitted entirely (not `false`) unless the
  directory was cut off by `-L` before being expanded.
- Files never have a `children` key; directories always do (possibly
  `[]`).

## Reading it back

`diff.c` parses exactly this shape back in via `json.c`'s bundled
minimal JSON reader (`json_parse` and friends) to implement `-o DIFF`
-- flattening the `tree` node recursively into a path-keyed table
before comparing against a freshly-scanned tree. That reader is
deliberately not a general-purpose/hardened JSON parser: it only ever
has to round-trip what `ltree` itself wrote.
