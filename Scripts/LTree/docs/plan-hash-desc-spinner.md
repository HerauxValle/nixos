<!-- &desc: "The category-by-category implementation plan and flagged design-decision ASSUMPTIONs for --stdout-aware lazy hash computation, --simple-hash, the lt binary alias, -o DESC/--desc/-D, and the loading spinner, all 6 categories shipped; original raw prompt appended verbatim at the bottom." -->

# Plan: --stdout-aware lazy compute, --simple-hash, lt alias, -o DESC/--desc/-D, loading spinner

Everything in this doc implements the spec at the bottom
(`## Initial prompt (verbatim)`) -- a single stream-of-consciousness
message covering five related asks that came out of the user noticing
`ltree` visibly hangs on large directories and suspecting full-file
hashing was part of why.

Continues the version sequence from `ltree-v12.tar.gz` (the ls-mode
rework); six new categories below, `ltree-v13.tar.gz` .. `ltree-v18.tar.gz`.

## Delivery convention (implementation phase only, not this doc)

Same as the ls-mode rework: after finishing and smoke-testing each
category, tar the project with an incrementing version:

```sh
cd ~/Dotfiles/Scripts/LTree
tar --exclude=result --exclude='.ltree' --exclude=build -czf ~/Downloads/ltree-v<N>.tar.gz .
```

---

## Category 13: `--stdout`-aware lazy computation (bug fix, done first)

The prompt's "only do what the user specified... if eg no hash is in
-o then there is no reason to do so... only on exclude and include" was
already *mostly* true before this batch: `need_hash` in `main.c`
already skipped hashing unless `-o HASH`, `-o DIFF`, or `--save-output`
asked for it, and plain `-j` with no `--stdout` filter was already
correctly lazy (documented in `docs/json-schema.md`). The actual gap
was `--stdout exclusive|inclusive <MODULES>`: naming `HASH` there
forces JSON output that's supposed to contain `"hash"`, but nothing
checked `cfg.stdout_filter`/`stdout_filter_keys` when deciding whether
to actually compute it -- `--stdout inclusive HASH` silently came back
`null`.

Fixed by exposing `json_key_allowed()` (previously `json.c`-internal)
and adding `field_wanted()` in `main.c`:

```c
static bool field_wanted(const Config *cfg, ModuleId id) {
    if (cfg->modules[id]) return true;
    if (cfg->save_output) return true;
    if (cfg->stdout_filter != STDOUT_FILTER_NONE) return json_key_allowed(cfg, id);
    return false;
}
```

`need_hash` became `field_wanted(&cfg, MOD_HASH) || cfg.modules[MOD_DIFF]`.
This is also the exact rule Category 16's `need_desc` resolves with --
one shared "is this worth computing" predicate instead of two
hand-written copies.

## Category 14: `--simple-hash`

"does it really make sense to hash the entire file? ... whatever is
efficient no matter the hash type (also for cryptog.) and the size of
the file."

Still dispatches through the existing `hash_compute()` (unchanged for
both xxHash64 and SHA-256) -- the sampling happens one layer up in
`scan.c`. Files `<= 128KiB` (2x the chosen 64KiB chunk) hash whole,
same as always; larger files hash a small fixed buffer instead:
`[size as 8 bytes][first 64KiB][last 64KiB]`. Since the file's already
`mmap`'d, only the touched head/tail pages actually get read off disk.
A static, reused scratch buffer (`g_simple_hash_scratch`) avoids
malloc/free churn per file -- this is a single-threaded,
one-scan-per-process tool, same convention as `render_tree.c`'s
`g_depth` statics.

**ASSUMPTION:** 64KiB chosen as "generous enough to still catch most
real edits (which cluster near file start/end -- headers, trailing
config, appended logs) without reading gigabytes." Not tunable via a
flag; if this turns out wrong in practice, revisit the constant rather
than adding a size knob nobody asked for.

**Consistency with `-o DIFF`:** a snapshot hashed with `--simple-hash`
compared against a run without it (or vice versa) would show every
large file as modified -- same class of problem `diff_peek_algo()`
already solved for xxHash64-vs-SHA-256. Extended the same function to
also read back a new `"hash_sampled"` JSON field and force
`cfg.simple_hash` to match the snapshot's, regardless of the current
run's own flags.

## Category 15: `lt` binary alias

"also in binary, i belive its in scripts.nix linked? add 'lt' besides
'ltree' as bin name aswell." -- the file in question is `flake.nix`'s
`installPhase` (there's no `scripts.nix` in this project; this is what
actually links the binary into the Nix store path the user's system
consumes via `inputs.ltree` in
`Nixos/config/software/packages/registry.nix`). Added
`ln -s ltree $out/bin/lt` right after the existing `cp`.
`meta.mainProgram` stays `"ltree"`.

## Category 16: `-o DESC` + `--desc <format>` / `-D <format>`

Designed directly around this project's own header-comment convention
-- every `.c`/`.h` file here starts with a `/* &desc: "..." */` line,
and `-o DESC`'s default format is exactly that: `&desc: "..."`.

**Format parsing:** split the format string on the literal substring
`"..."`. Everything before it is the search prefix; everything after
it is the closing suffix. The prompt's framing ("`&description` is the
start marker, `:` is the separator... the direct left and right real
character means marker for start and end") all falls out of that one
plain split automatically -- no special-casing of "the character
touching the dots" was needed. Both sides must be non-empty (rejected
otherwise): an empty prefix would match everywhere in a file; an empty
suffix would capture nothing, every time.

**ASSUMPTION (search bounds, not spelled out in the prompt):** only the
first 64KiB of a file is searched for the prefix (this project's own
`&desc:` comments always sit at the very top), and the closing suffix
is only looked for within 4096 bytes after a prefix match -- past that,
treated as no match rather than scanning arbitrarily far into a large
file just to rule one out. Flagging this for a look, not blocking --
easy to loosen later if a real use case needs a marker deeper in a file.

`-D` added as a literal alias for `--desc`, deliberately distinct from
the existing lowercase `-d` (dirs-only) -- the prompt was emphatic about
this ("NOT -d!!!").

`RENDER_COLUMN_COUNT` went from 6 to 7 to give `DESC` its own aligned
`[DESC: ...]` column through the exact same `columns.c` measure/print
pipeline every other column already uses (no new rendering path).

## Category 17: loading spinner (non-`--live` and `--live`)

"if --live is not given add a animated loading thingy so its clear
that its doing smth and not stuck. if --live is given show a loading
one (the same) always at the most bottom one."

New `util/spinner.h`/`spinner.c` -- a 10-frame braille spinner, writes
only to **stderr** (keeps `-j`/piped stdout untouched) and only draws
when stderr is a tty (so `tools/smoke_test.sh`, which runs everything
non-interactively, is a no-op by construction -- verified, not just
assumed). Rate-limited to ~90ms between redraws unless forced, so a
scan finishing faster than that never draws anything at all.

**Without `--live`:** `scan.c`'s `build_tree()` ticks it once per
directory entry processed (the actual "large dir, many files hashed"
case this whole batch started from) -- nothing else prints until the
walk finishes, so `main.c` just starts it before the walk and stops
(erases) it right after, before the buffered view prints.

**With `--live`:** same per-entry ticking during the walk, plus every
real line `render_tree.c` streams to stdout (`tree_live_start`'s header,
`tree_live_on_entry_ready`'s per-entry print) is wrapped in
`spinner_erase()` before / `spinner_tick(true)` after -- so it's always
erased before a real line prints and immediately redrawn underneath it,
satisfying "always at the most bottom one." Verified interactively
under a real pty (`script`): the spinner visibly animates through
frames in both modes and ends cleanly erased, with zero effect on the
83/83 smoke-test suite (confirming the tty gate holds under the
non-interactive harness).

## Category 18: docs

This file, plus updates to `README.md`, `docs/usage.md`,
`docs/architecture.md`, and `docs/json-schema.md` covering every
category above, and new `smoke_test.sh` coverage for: `--stdout
inclusive HASH` actually computing a hash without `-o HASH`,
`--simple-hash` on a large file, `-o DESC` with both the default and a
custom `--desc`/`-D` format, and a malformed `--desc` being cleanly
rejected.

---

## Initial prompt (verbatim)

> in larger dirs like [Image #2] it takes a long time, i assume its bc
> of hashing, though, does it really make sense to hash the entire
> file? also in binary, i belive its in scripts.nix linked? add "lt"
> besides "ltree" as bin name aswell. and per hash... --save-output
> should do the full json output like rn. but if i dont have save
> output then there is no need to do everything. on no json output
> same for the std thing. only do what the user specified. if eg no
> hash is in -o then there is no reason to do so. only on exclude and
> include ... i think u get what i mean. and --simple-hash if hash is
> enabled to maybe not hash the entire file but only maybe ... i dunno...
> whatever is efficient no matter the hash type (also for cryptog.) and
> the size of the file. also to -o add "DESC" and --desc <format> ill
> explain: if i give DESC in o it searches each file for a "&desc: "xxx""
> and outputs xxx. --desc allows to set what it searches for so instead
> of &desc it searches for eg --desc "&description: *...*" where
> &description is the start marker, : is the seperator, can be
> anytthing lol... the only thing that really is mattering "..." the
> three dots always means here is the description. and the direct left
> and right real character (no space etc) means marker for start and
> end. add -D which is --desc just alias ( NOT -d!!!). if --live is not
> given add a animated loading thingy so its clear that its doing smth
> and not stuck. if --live is given show a loading one (the same)
> always at the most bottom one., path is: Dotfiles/Scripts/Ltree
> (captilization may differ!). Write a plan then execute the plan and
> test.
