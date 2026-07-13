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
  "total": {
    "dirs": 4,
    "files": 6,
    "lines": 10,
    "chars": 312
  },
  "by_extension": [
    { "ext": "c", "files": 1, "lines": 3, "chars": 24 }
    // sorted by lines descending, ties broken alphabetically by ext;
    // extensionless files use "ext": "(no ext)"
  ],
  "tree": { /* the root node, see below */ }
}
```

`hash_algo` is `"none"` whenever nothing in the run actually needed a
digest (no `-o HASH`, `-o DIFF`, or `--save-output`) -- hashing is
otherwise skipped entirely, not just hidden from output.

`by_extension` is always present, even for `-j` calls that didn't
request `-o FILES` -- unlike the terminal view, the JSON output isn't
gated by which `-o` modules were passed; it always carries everything
`ltree` computed during the scan. `-o EXT`/`-o HASH` etc. only affect
what the *tree view* prints, not what the JSON contains.

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
