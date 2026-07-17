<!-- &desc: "Design-decision record (hashing algorithm choice, DATE timezone, monolith-vs-modules split, column-alignment layout) from when PERMISSIONS/SIZE/DATE/HASH/--gitignore/--save-output/-o DIFF were first added, predating the later ls-mode rework." -->

# Design decisions

This records the decisions made while adding `PERMISSIONS`, `SIZE`,
`DATE`, `EXT`, `HASH`, `--gitignore`, `--save-output`, and `-o DIFF`
on top of the original line/char counter + JSON exporter, so the
reasoning doesn't have to be reconstructed from the diff later.

## Hashing: default algorithm

**Question:** for `-o HASH`, prioritize raw speed (non-cryptographic,
e.g. an xxHash-style construction -- great for change detection, but
two different files could theoretically collide) or go cryptographic
(e.g. SHA-256 -- slower, but collision-safe, better if hashes might
ever be trusted for integrity/security)?

**Decision:** default to the fastest option (xxHash64). `--cryptographic`
opts into SHA-256 instead. Rationale: the primary use case sitting
right next to `HASH` is `-o DIFF` -- "did this change since last
time" -- which is a change-detection problem, not an integrity
problem. A 64-bit digest is already astronomically collision-safe for
that purpose, and defaulting to the cheap option keeps a full-tree
hash-everything scan fast on large trees. Anyone who actually wants
to *trust* the digest (e.g. feeding it somewhere security-relevant)
opts in explicitly.

If no previous `.ltree` snapshot exists for `-o DIFF` to compare
against, this is surfaced as a small note at the end of the output --
not a warning, not a non-zero exit, just a note, since "first run, no
snapshot yet" is the expected steady state the first time you use
`DIFF` in a new directory.

## Hashing: which algorithm does DIFF use?

Corollary decision, since `--cryptographic` and `-o DIFF` can disagree:
if a previous snapshot exists, `-o DIFF` **always hashes the current
scan with whichever algorithm produced that snapshot**, regardless of
what `--cryptographic` says on the current invocation. Comparing an
xxHash64 digest against a SHA-256 digest is meaningless, and silently
falling back to size/mtime comparison would be a worse and more
confusing default than just using the snapshot's own algorithm. The
snapshot's algorithm is read from its `hash_algo` field
(`diff_peek_algo` in `diff.c`) *before* the scan starts, so the scan
itself hashes with the correct algorithm the first time -- no
re-hashing pass needed. `--cryptographic` still governs `-o HASH`'s
own display and any snapshot this run itself writes via
`--save-output`.

## DATE and timestamp timezone

**Question:** for `-o DATE` and the `--save-output` snapshot filename,
local system timezone, or UTC?

**Decision:** local timezone for both. A directory listing is
something a person is looking at, at their desk, right now --
`ls -l`-style tools use local time for the same reason, and matching
that convention means the `[D: ...]` column and the snapshot filename
both read the way the user already expects a file timestamp to read.

## Monolith vs. split into modules

**Decision:** split. See `docs/architecture.md` for the resulting
module map and the reasoning in full -- in short, once this many
independent features (scanning, six different render columns, JSON
read *and* write, gitignore matching, two hash algorithms, snapshot
persistence, and tree diffing) sit on top of the original counter, a
single file stops being the readable option. Each module's job fits
in one sentence, and several of them (the JSON writer/reader pair,
the two hash algorithms behind one dispatch function) are genuinely
shared by more than one feature -- which a monolith would either
duplicate or entangle.

## Visual layout for multiple `-o` columns

The original single-bracket-per-line format doesn't scale past two or
three modules -- see `docs/usage.md`'s "Column alignment" section for
the resulting design: one bracket per module, each column
independently width-aligned across the whole tree, fixed order
regardless of `-o` argument order, fixed 3-space gap between columns,
and entry brackets all starting 8 characters past the widest
name+prefix in the tree. `-o DIFF`'s `[m]` flag rides along after
everything else rather than getting its own aligned column, since
it's boolean and only ever appears on the (typically few) modified
entries -- aligning a column that's blank on most lines would waste
width for no readability gain.
