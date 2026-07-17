# Plan: default ls-mode, -oE, HIDDEN, --condense, -o O, --sort, live output, stdin/--stdout

Everything in this doc implements the spec at the bottom (`## Initial prompt (verbatim)`).
That prompt was typed into claude.ai right before an outage cut the session, so
"continue where u left off" just means "this file is the spec, start from it" --
there is no earlier draft anywhere else to reconcile against.

Two things were confirmed with the user before writing this plan:

1. The default output mode **flips**: `ltree` with no args currently prints the
   recursive tree view. After this work, no-args `ltree` prints the new
   ls-style grouped `[Folders]`/`[Files]` listing instead, and the old tree
   view becomes opt-in via `-o TREE`.
2. `-o O` means: normally `-o LINES,CHARS` always renders columns in the fixed
   `L,C,P,S,D,H` order regardless of argument order; adding `O` to the list
   (e.g. `-o CHARS,LINES,O`) makes rendering follow the order you typed
   instead.

One thing from the raw prompt is **not** a new requirement, just a
restatement: "the stuff behind the f and ds" meant "files and dirs", and the
point was that `EXT` (extension display) stays opt-in the same way in both
tree mode and ls mode -- that's already how `EXT` behaves today, nothing to
build.

Everywhere below marked **ASSUMPTION** is a call made under the prompt's own
"you can modify, u get the idea" license, because the raw text didn't spell
it out. Flag these for a quick look before/while implementing, not blocking.

## Delivery convention (implementation phase only, not this doc)

Per the prompt: after finishing and smoke-testing each main category below,
tar the project with an incrementing version:

```sh
cd ~/Dotfiles/Scripts/LTree
tar --exclude=result --exclude='.ltree' -czf ~/Downloads/ltree-v<N>.tar.gz .
```

`<N>` starts at 1 and increments once per completed category (Category 0 ->
v1, Category 1 -> v2, ...). This doesn't apply to writing this plan itself,
only once implementation starts.

---

## Category 0: unify the module table (do this first, everything else builds on it)

**Why first:** the prompt itself asks "reason about if that's the cleanest
implementation cuz flags and LINES like those capital things are getting
messy" before writing the plan. It's justified -- there are currently **two
separate, hand-duplicated** enumerations of "what a module is":

- `main.c`'s CLI parser: an `if/else strcasecmp` chain over `LINES, CHARS,
  TOTAL, FILES, PERMISSIONS, SIZE, DATE, EXT, HASH, DIFF, DEBUG`, each
  setting one `bool cfg.o_*` field (`core/config.h:25-35`).
- `render/render_tree.c`'s **own, local, six-entry-only** `ModuleId` enum (`MOD_L,
  MOD_C, MOD_P, MOD_S, MOD_D, MOD_H` at `render/render_tree.c:111`) with its own
  `module_active()` switch translating back from `cfg.o_*` -- duplicating
  the same six names a second time, in a second order-of-truth.

Adding `TREE`, `HIDDEN`, `-oE`, and `-o O` on top of that duplication, by
hand, in both places, is exactly how this gets messier. Fix: introduce one
shared table both files read from.

**New file:** `include/core/modules.h` / `src/core/modules.c`

```c
typedef enum {
    MOD_LINES, MOD_CHARS, MOD_PERM, MOD_SIZE, MOD_DATE, MOD_EXT, MOD_HASH,
    MOD_TOTAL, MOD_FILES, MOD_DEBUG,
    MOD_DIFF,
    MOD_TREE, MOD_HIDDEN,
    MOD_COUNT
} ModuleId;

typedef enum {
    MODCAT_COLUMN,   /* LINES/CHARS/PERM/SIZE/DATE/EXT/HASH -- own [X: ...] bracket per entry */
    MODCAT_SUMMARY,  /* TOTAL/FILES/DEBUG -- end-of-run blocks, not per-entry            */
    MODCAT_DIFF,     /* DIFF -- own thing, marks entries + trailing note                 */
    MODCAT_TOGGLE    /* TREE/HIDDEN -- change WHAT is walked/how it's laid out, not a column */
} ModuleCat;

typedef struct { const char *name; ModuleId id; ModuleCat cat; } ModuleDef;

extern const ModuleDef MODULE_TABLE[MOD_COUNT]; /* core/modules.c, indexed by ModuleId */

const ModuleDef *module_lookup(const char *name); /* case-insensitive, NULL if unknown */
```

`core/config.h` changes `bool o_lines; bool o_chars; ...` (11 separate fields) to
a single `bool modules[MOD_COUNT];` array, plus `bool o_order;` (for `-o O`,
not a real module -- see Category 5) and `bool o_hidden` is just
`modules[MOD_HIDDEN]`, no separate field needed.

**Files touched by the rename** (grep `cfg.o_\|cfg->o_` across the tree to
catch every call site before starting):
`main.c`, `render/render_tree.c`, `render/render_files.c`, `io/json.c`, `debug/debug.c`, `io/save.c`,
`io/diff.c` -- every `cfg->o_lines` becomes `cfg->modules[MOD_LINES]`, etc.
Mechanical, but touches ~7 files, so do it as its own commit before adding
any new flag, so later diffs are readable.

**`main.c`'s `-o` parser** becomes a loop over `strtok(val, ",")` calling
`module_lookup()` and setting `cfg.modules[def->id] = true`, instead of the
11-way `if/else`. `-oA`/`-o A` still means "every `MODCAT_COLUMN` +
`MODCAT_SUMMARY` + `MODCAT_DIFF` module" (see Category 1 for why `TREE`/
`HIDDEN` are deliberately excluded from what `A` means).

**`render/render_tree.c`** drops its local `ModuleId`/`module_active()` and reads
`cfg->modules[MOD_LINES]` etc. directly, or takes an `active[]` bool array
sliced from `cfg->modules` for just the `MODCAT_COLUMN` ids -- either way,
one source of truth.

---

## Category 1: `-oE` (exclude modules)

Mirrors `-oA` but inverted: "every module except the ones named."

**Syntax:** first token in the comma list is `E` (case-insensitive), same
shape as how `A` is currently detected as a token anywhere in the list
(`main.c:117-123`). Both forms work:

```
-o E,LINES,CHARS      # space form
-oE,LINES,CHARS       # glued form (comma required right after E)
```

Unlike `A`, `E` **requires** a following list -- `-oE` / `-o E` alone with
nothing after the comma is a usage error ("nothing to exclude"), since
"everything except nothing" is just `-oA` spelled worse.

**Scope (ASSUMPTION):** `A` and `E` only operate over `MODCAT_COLUMN` +
`MODCAT_SUMMARY` + `MODCAT_DIFF` (the original 11 "what shows in the
output" modules) -- **not** `MODCAT_TOGGLE` (`TREE`, `HIDDEN`). Reasoning:
"give me everything" as a display concept shouldn't have the side effect of
also flipping the output mode or revealing dotfiles; those are behavior
switches, not content. So `-oA` and `-oE,LINES` both leave `TREE`/`HIDDEN`
exactly as their own flags left them.

**Implementation:** in the new `-o` loop (Category 0), detect `E` as the
first token the same way `A` is detected today; if found, collect the
remaining tokens as the exclusion set, validate every excluded name against
`module_lookup()` (reject unknown names same as today's "unknown -o module"
warning), then set `cfg.modules[id] = true` for every `MODCAT_COLUMN` /
`MODCAT_SUMMARY` / `MODCAT_DIFF` id **not** in the exclusion set. Reject
`-o A,E,...` or `E` combined with `A` in the same list (nonsensical, same
class of error as today's `-o A,DEBUG` rejection).

---

## Category 2: `-o TREE` + the new ls-mode default

This is the biggest behavioral change and the one the prompt was least
precise about, so the design below is spelled out in full.

**Today:** no-args `ltree` walks recursively (respecting `-L`) and prints
the connector tree (`├──`/`╰──`) via `print_tree_view()` in `render/render_tree.c`.

**After this category:** no-args `ltree` prints a **flat, non-recursive,
grouped listing of the given directory only** -- like plain `ls`, per the
prompt's own "i want you to natively with no args or anything work like
base ls." `-o TREE` brings back exactly today's recursive connector view,
unchanged, still honoring `-L`.

**ASSUMPTION, flagged explicitly:** the prompt never says "non-recursive"
in so many words, but "work like base ls" only makes sense that way -- real
`ls` doesn't recurse. `-L` becomes meaningless in the new default mode (ls
mode always shows exactly one directory's direct children) and only applies
again once `-o TREE` is present. If this reading is wrong, everything below
in this category is the part to redo -- nothing else in the plan depends on
which way this lands.

**Layout (from the prompt, this part is explicit):**

```
[Folders]
  <dir entries, coloured like ls -la, sorted per --sort (Category 6)>
  <hidden dir entries appended here, only if -o HIDDEN>
[Files]
  <file entries, same rules>
  <hidden file entries appended here, only if -o HIDDEN>
```

Per-entry `-o` columns (`LINES`, `CHARS`, `PERMISSIONS`, ...) still render
per row exactly as they do in tree mode -- same `[X: ...]` brackets, same
alignment pass -- just without the `├──`/`│`/`╰──` connector prefix, since
there's no tree structure to draw in flat mode.

**New files:** `src/render/render_ls.c` / `include/render/render_ls.h`,
mirroring `render/render_tree.h`'s existing shape:

```c
void print_ls_view(Node *root, const char *display_path, const Config *cfg,
                    const Totals *tot, bool diff_available, const DebugStats *dbg);
```

Reuses the same "flatten to `PrintLine`s, measure column widths, print"
pipeline as `render/render_tree.c` (factor the column-measuring/printing block
into a shared helper both `render/render_tree.c` and `render/render_ls.c` call, rather
than copy-pasting it -- see `render/render_tree.c:100-246` for the block to
extract). The only real difference is `flatten()`: instead of walking the
whole subtree with connector prefixes, it does one `readdir()`-depth pass,
splits into two `PrintLine` arrays (`is_dir` vs not), and the printer emits
the `[Folders]` header + array, then `[Files]` header + array.

**`main.c` dispatch** (currently `main.c:259-264`):

```c
if (cfg.json) {
    print_json(...);
} else if (cfg.modules[MOD_TREE]) {
    print_tree_view(...);              /* today's behavior, unchanged   */
    if (cfg.modules[MOD_FILES]) print_files_summary(...);
} else {
    print_ls_view(...);                /* NEW default                   */
    if (cfg.modules[MOD_FILES]) print_files_summary(...);
}
```

**Scanning:** when `-o TREE` is absent, `build_tree()` (`scan/scan.c`) should
only be called with effective depth `0` (direct children only) instead of
walking the full subtree -- don't build a tree you're not going to show.
`-L` continues to control depth only when `-o TREE` is present.

---

## Category 3: `-o HIDDEN`

Default off (matches today's implicit behavior -- dotfiles aren't shown).

**Scan-level filter, not just display:** `scan/scan.c`'s `build_tree()` already
unconditionally skips `.ltree` (the snapshot dir, see `docs/usage.md`'s
"Exclude / gitignore matching" section). Generalize that one hardcoded skip
into: always skip `.ltree`; skip any other entry whose basename starts with
`.` **unless** `cfg->modules[MOD_HIDDEN]` is set. One extra `bool` check
next to the existing `.ltree` check in `build_tree()`.

**Placement:**
- ls mode: hidden dirs/files append **after** the visible ones within their
  own `[Folders]`/`[Files]` block, per the prompt ("once the list of folders
  is over put ... the hidden files also in"). Simplest implementation:
  sort visible-then-hidden as a two-key sort (`is_hidden` first, name
  second) within each block, rather than a separate third block.
- tree mode (`-o TREE`): no special placement rule was given for tree mode,
  and tree mode doesn't have Folders/Files blocks to append within, so
  hidden entries just sort into their normal alphabetical position
  alongside everything else at that depth.

---

## Category 4: `--condense`

Collapses the per-module bracket sequence into one bracket, same colours.

Before:
```
[L: 10]   [C: 312]   [P: -rw-r--r--]
```
After (`--condense`):
```
[L:10 C:312 P:-rw-r--r--]
```

**Implementation:** in the shared column-printing helper (Category 2), add
`cfg->condense`. When false, keep today's behavior (one `[`...`]` pair per
active module, 3-space gap between). When true: print a single leading `[`,
then for each active module print its already-colour-wrapped text with a
single space separator (no per-module brackets, no 3-space gap), then a
single trailing `]`. Width-measurement pass is unchanged; only the
delimiter/bracket emission at print time changes.

---

## Category 5: `-o O` (respect argument order)

Not a real module -- like `A`/`E`, it's a modifier token detected in the
`-o` list, e.g. `-o CHARS,LINES,PERMISSIONS,O`. Store as `cfg.o_order`
(plain `bool`, not in `modules[]`, since it doesn't turn anything on/off by
itself -- it only changes the order of whatever *is* on).

**Effect:** today, `render/render_tree.c`'s column loop always iterates
`MOD_LINES, MOD_CHARS, MOD_PERM, MOD_SIZE, MOD_DATE, MOD_HASH` in that fixed
order (`render/render_tree.c:230`, using a hardcoded `order[]`). With `cfg.o_order`
set, iterate instead in the order the module names appeared in the original
`-o` argument string -- so `-o CHARS,LINES,O` prints the `[C: ...]` bracket
before `[L: ...]` on every line. Requires the `-o` parser (Category 0) to
also record arrival order (a small `ModuleId order_seen[MOD_COUNT]; int
n_order_seen;` alongside `cfg.modules[]`), which the renderer reads when
`cfg.o_order` is set, falling back to the fixed table order otherwise.

**Combinability:** rejected in combination with `A` (same error class as
`-o A,DEBUG` today) -- "every module, in the order I typed them" is
incoherent once `A` already means "all of them, full stop." Fine combined
with `E` (exclude a few, then order the rest as typed).

---

## Category 6: `--sort`

New flag, **ls-mode only** (per the prompt: "--sort applies only to ls").
If passed together with `-o TREE`, print a warning to stderr and ignore it
-- same leniency class as "unknown -o module", not a hard error.

**Syntax:** `--sort <mode>[,<mode>...]`

| mode | meaning |
|---|---|
| `abc` | alphabetical, `[Folders]` block then `[Files]` block (this is also the **default** when `--sort` isn't passed at all) |
| `birth` | sort by creation time |
| `modified` | sort by last-modified time (newest at the bottom, matching how `DATE` already reads) |
| `lines` | sort by line count (file with the most lines at the bottom) |
| `chars` | sort by char count (most at the bottom) |
| `types` | bucket the `[Files]` block into per-extension sub-groups (`[py]`, `[md]`, ...), alphabetical by extension name, alphabetical within a bucket; `[Folders]` is unaffected (dirs don't have an extension in this project's model) |
| `combined` | modifier: don't split into `[Folders]`/`[Files]` -- one flat list, sorted by whatever the base mode is |
| `reversed` | modifier: reverses whatever ordering the base mode produces |

**Combinability rule (ASSUMPTION, prompt explicitly punts on the exhaustive
list and says "be careful about what can be combinable and what no"):**
`abc`/`birth`/`modified`/`lines`/`chars`/`types` are mutually exclusive base
keys -- passing two of them is a usage error, same class as `-o A,DEBUG`.
`combined` and `reversed` are modifiers, combinable with any one base key
and with each other. `combined` + `types` is rejected (both are grouping
strategies, they conflict) -- warn + ignore `combined` if both given.

**Implementation:** new `src/sort/sortmodes.c` / `include/sort/sortmodes.h`
exposing one `qsort`
comparator selected by `cfg->sort_mode` + `cfg->sort_reversed` +
`cfg->sort_combined`, used by `render/render_ls.c` right before splitting/printing
the Folders/Files (or combined, or per-type) blocks. `node_cmp()` in
`core/node.c` stays as-is (still used by tree mode, which isn't affected by
`--sort`).

---

## Category 7: live/streaming output

**Real architectural tension, flagged up front:** today, `main.c` calls
`build_tree()` to walk the *entire* subtree into memory first, and *then*
`print_tree_view()`/`print_ls_view()` do a first pass over the *whole*
already-built tree just to measure each column's max width before printing
anything (`docs/usage.md`'s "Column alignment" section: "padded to its own
widest value across the whole tree"). True incremental printing -- show an
entry the instant it's scanned -- is incompatible with "align columns to
the widest value anywhere in the tree," because you don't know that value
until the walk finishes.

**Decision (ASSUMPTION):** add this behind a new `--live` flag, opt-in,
default behavior (no `--live`) is **completely unchanged**. With `--live`:
column alignment relaxes from whole-tree to **per-directory-block** --
once a directory's direct children are fully scanned, its own rows get
printed immediately, aligned to each other, and stdout is flushed. This is
a real, documented behavior difference from non-live mode (columns won't
line up *across* different directories' blocks the way they do today), not
a bug -- call it out in `docs/usage.md` when this ships.

**Implemented as built (revises the sketch above):** `build_tree()`
(`scan/scan.c`) was split into two phases so the callback fires *before*
recursing rather than after (the original one-pass version could only fire
depth-first-last, printing the deepest directories first -- backwards from
what anyone watching live output would expect). Phase 1 does the `readdir()`
loop: files are fully scanned, subdirectories are created and marked
`truncated` (or not) but not yet descended into. Once that directory's own
`children` are sorted and attached, `DirReadyFn on_dir_ready(Node *dir,
const char *relpath, const Config *cfg, void *ctx)` fires -- *then* Phase 2
recurses into whichever children can still descend. Net effect: `--live`
streams top-down (root's own listing, then each subdirectory's as it's
entered), not bottom-up.

Turned out **not** to be ls-mode-only. Since ls mode (Category 2) is
already non-recursive, `--live` has little to stream there -- one directory,
one block, done. The actual "large dir takes a while" problem the original
prompt described only shows up with deep recursion, which only happens in
`-o TREE`. So `--live` works with **both** modes, using its own third
rendering path (`render/render_live.h` / `render_live_dir_block()`) -- a
flat `path/:` header + indented children per directory block, *not* a
live-updating version of either the connector tree or the `[Folders]`/
`[Files]` grouping. `-o TREE --live` prints every directory's block as
soon as it's scanned, in the same top-down order, just without connector
glyphs; the classic connector tree is only ever available in its full,
whole-tree-aligned, non-live form. Rejected instead: `--live -j` (JSON
needs the complete tree before it can emit one value) -- warned and
ignored, same leniency class as `--sort` + `-o TREE`.

`TOTAL`/`FILES`/`DEBUG`/the DIFF note still print once, at the very end,
same as before -- factored into a shared `print_summary_tail()`
(`render/columns.c`) since `render_tree.c`, `render_ls.c`, and now `main.c`
(for the `--live` path, which skips both view functions entirely) all need
the exact same tail.

---

## Category 8: stdin as path input

If no positional `path` argument was given **and** stdin is not a TTY
(`!isatty(fileno(stdin))`), read one line from stdin, strip the trailing
`\n`/`\r`, and use it as `cfg.path`. Otherwise (no path arg, stdin is a
TTY), keep today's default of `"."`. One change, right at
`main.c:178` (`if (!cfg.path) cfg.path = strdup(".");`), no new flag.

```c
if (!cfg.path) {
    if (!isatty(fileno(stdin))) {
        char buf[PATH_MAX];
        if (fgets(buf, sizeof(buf), stdin)) {
            buf[strcspn(buf, "\r\n")] = '\0';
            cfg.path = strdup(buf);
        }
    }
    if (!cfg.path) cfg.path = strdup(".");
}
```

(`#include <unistd.h>` for `isatty`, already pulled in transitively via
other POSIX headers this project already uses -- verify and add explicitly
if not.)

---

## Category 9: `--stdout <exclusive|inclusive> <KEYLIST>`

Forces JSON output (like `-j`) additionally filtered to a subset of keys.

**Syntax (two argv tokens, matching the prompt's own example literally):**
```
ltree --stdout exclusive TREE,LINES
ltree --stdout inclusive PERMISSIONS,DATE
```
`KEYLIST` uses the same names as `MODULE_TABLE` (Category 0) plus `TREE`
meaning "the tree/entries structure itself." `exclusive <LIST>` = emit
everything `-j` would, except the named keys. `inclusive <LIST>` = emit
**only** the named keys (plus whatever's structurally required to keep the
JSON valid, e.g. `name`/`type` per entry -- those are never filterable).

**Implementation:** `core/config.h` gets `enum { STDOUT_FILTER_NONE,
STDOUT_FILTER_EXCLUSIVE, STDOUT_FILTER_INCLUSIVE } stdout_filter;` +
`ModuleId stdout_filter_keys[MOD_COUNT]; int n_stdout_filter_keys;`.
`json_render()` (`io/json.c`) checks the filter before emitting each
optional block/field -- a small `bool json_key_allowed(const Config *cfg,
ModuleId id)` helper, called at each of the existing per-module `if
(cfg->modules[...])`-style emission points already in `io/json.c`. `--stdout`
implies `cfg.json = true` the same way passing it should make `-j` redundant
but not conflicting if both are given.

---

## Category 10: TOTAL/FILES formatting consistency + note-at-bottom

Two small, independent fixes, both about existing output, no new flags.

**1. Bracket-style consistency.** Per-entry columns use `[X: value]`
brackets; `TOTAL:`/`FILES:` currently don't (`render/render_tree.c:255-261`,
`render/render_files.c`) -- they're plain `label: value` lines. Restyle both to
match:
```
TOTAL:
  [dirs: 4]   [files: 6]   [lines: 10]   [chars: 312]

FILES:
  [TYPE: c]   [FILES: 1]   [LINES: 3]   [CHARS: 24]
  [TYPE: py]  [FILES: 1]   [LINES: 2]   [CHARS: 18]
  ...
```
Same column-alignment convention as everywhere else (pad each bracket to
its own widest value across all rows in that block, fixed 3-space gap).

**2. Note always last.** Confirmed by reading `render/render_tree.c:255-270`: the
DIFF "no previous snapshot" note **already** prints after `DEBUG` in the
current code (`TOTAL` -> `DEBUG` -> note, in that order). This part of the
prompt is **already satisfied** -- no fix needed here, just make sure
`render/render_ls.c` (Category 2, new file) follows the identical order: Folders/
Files blocks -> `TOTAL` -> `FILES` (if requested) -> `DEBUG` -> DIFF note,
last, always.

---

## Category 11: docs

Once the above lands: update `README.md`'s usage block and examples,
`docs/usage.md`'s flag table and `-o` module list, and add a new "Design
decisions" section to `docs/plan.md` (or leave this file `docs/
plan-ls-rework.md` as the permanent record, matching how `docs/plan.md`
itself is described as "records the decisions ... so the reasoning doesn't
have to be reconstructed from the diff later") covering: the `modules[]`
unification (Category 0), the ls-mode-is-non-recursive assumption
(Category 2), and the live-mode alignment trade-off (Category 7) -- those
three are the calls most likely to get second-guessed later.

---

## Initial prompt (verbatim)

make Totals stuff and files stuff consistent with the rest. the note: should always be at the tobbom and then add -oE
 which accepts anything like -o after but instead of including it it excludes it. aka its oA but without the mentioned stuff after. continue where u left off. also add TREE into -o because i want you to nativly with no args or anything work like base ls. obv with colour thoi unless no colour flag. to -o add
 HIDDEN which shows hidden files like the . ones (now on default off) and --condense puts the currently seperated blocks lie L: C: etc ineo one [] thingy still colourcoded the same tho... and to -o add O (can be combined) it just means to apply the order what comes after -o so if i do CHARS,LIST it doesnt use the default list then char. obv doesnt make sense with oA lol. and btw, i think thats logical the stuff beind the f and ds only show when tree is in -o... but they can still show if tree is not there because of normal ls behaviour i mentioned. ltree without anything seperates all folders and files where folders are top as [Folders] then once the list of folders is over put if hidden is applied the hidden files also in and then [Files] everything is properly colourcoded. same hidden after normal files here. --sort applies only to ls. --sort abc sorts alpahabetically first folders then files. --sort abc,combined sorts alphabetically withouit seperating folders and files --sort birth (combinable where it makes sense, i wont give endless examples, but u get the
 point) sorts for when the files was created, --sort modified for last modified (in abc a is at the end of output. in dates the newest / latest modified at the bottom aswell) --sort reversed reverses everything mentioned in sort eg abc etc. also add live output, rn it gets the stuff then prints, for large dirs that can take long and be annoying. allow stdin, whats passed in will be used as path intput. stdout will be the json output if i do --stdout exclusive TREE,LINES it will exclude those from the output (make that make sense lol, i mean then there wont be really output ig, but u get what i mean) inclusive
 does the oppsoite. for --sort btw iu forgot lines for file with most lines (most at the bottom, same fo the following) chars aswell --sort types then alphabetically sorts in [<filetype>] so for .py it would show [py] applying the combinable stuff also. one thing: be carefull about what can be combinable and what no. everything about are the final goals, u can modify, u get the idea. write a plan... a detailled plan. in md. that has all steps on implementation that even the dumbest model would understand. also dont forget about oE xd. first reason about if thats the cleanest implemntation cuz flags and LINES like those captial things are getting messy. extract the files and also part the plan into main categories and sub categories. after each main category you output the tar.gz with a incremental version. this prompt i now wrote u also append exactly like that without modification at the bottom as initial prompt
