<!-- &desc: "What changed versus the Python original: two real bugs found and fixed, deliberate simplifications, and what was ported byte-for-byte on purpose." -->
# Porting notes: what changed versus the Python original

The goal of this rewrite was behavioral parity, not a redesign — every
action, flag, prompt, and message text was ported as-is unless noted
below. These are the exceptions, found by reading the original closely
enough to trace what it would actually do, not by guessing.

## Bugs fixed

### `cas <vault> info` always reported 0 active key slots

The original counted occurrences of the literal string `"ENABLED"` in
`cryptsetup luksDump` output. That marker only appears in **LUKS1**
dumps; this tool has only ever formatted **LUKS2** vaults (`--pbkdf
argon2id` implies LUKS2), and a real LUKS2 dump has no `"ENABLED"`
string anywhere — slots show up as `1: luks2` instead. Confirmed against
a real vault's header: it had exactly one active slot, and `info`
reported zero. `luks::slot_count()` now reuses the same slot parser
`find_used_slot`/`find_free_slot` already needed (which handles both
LUKS1 and LUKS2 dump formats), so the count is actually correct.

### `cas <vault> rename` with no argument silently renamed to `rename.img`

`cmd_rename` took the *last element of the entire argv* (`args[-1]`) as
the new name, rather than the rename-specific trailing argument. Since
`[vault, "rename"]` always has at least two elements by the time that
branch is reached, `cas myvault rename` (no name given) set
`new = "rename"` and proceeded to rename the vault with no error.
`commands/rename.rs` now looks only at its own trailing args and reports
`missing new name` when none is given.

### `cas <vault> resize` could permanently lose the metadata trailer on failure

`cmd_resize` called `meta_strip(img)` *before* its `try/finally` block,
and the code that restored it (`meta_write(img, meta)`) sat *after* that
block — reachable only if the whole resize succeeded. Any failure inside
the block (the shrink safety check's `die()`, a mount failure, a wrong
passphrase) left the trailer stripped for good: the vault's data was
untouched, but its 2FA keyfile association, `backup_auto` settings, and
encryption-bypass autokey were silently gone. `commands/resize.rs`
restores the trailer unconditionally before propagating any error,
matching the discipline `cmd_open` already used correctly.

## Deliberate simplifications (not behavior changes)

- **Secrets go over stdin, not temp files.** Every `cryptsetup` call
  needing one secret uses `--key-file -` instead of writing the secret
  to a temp file first — see `docs/architecture.md`. The one exception
  (`luksAddKey`, which needs two secrets at once) still uses temp files,
  now created with mode 0600 in the same syscall that creates them.
- **`Vault::find` returns one resolved struct** instead of the original
  calling `find_img()` twice in the `open` dispatch to get the same path
  both times.
- **`user_ids()` reads `SUDO_UID`/`SUDO_GID` directly** instead of
  shelling out to `id -u $SUDO_USER` / `id -g $SUDO_USER` — sudo always
  sets both env vars alongside `SUDO_USER`, so this is the same value
  without spawning two extra processes per privileged operation.
- **Privilege drop uses `Command::uid()`/`gid()`** (which sets the
  child's ids via `posix_spawn`) instead of Python's `preexec_fn`
  fork-time callback, which upstream's own docs flag as not
  async-signal-safe.
- **`backup auto enable/disable/keep`'s redundant `meta_strip()` before
  `meta_write()`** was dropped — `Meta::write()` already strips
  internally before appending, so the standalone call did nothing.

## Ported as-is, on purpose

- The `--pass`/`--new-pass` truthiness quirks (an explicit `--pass ""`
  is treated as "not given," `passwd --strength medium` is
  indistinguishable from no `--strength` at all) — these are the actual
  documented CLI contract, not incidental.
- `toggle`'s passphrase handling skips the shell-history warning and
  stdin-file-check `open`/`get_pw` do, since it's meant for a keybind
  where that noise doesn't belong.
- The exact wording of every `[i]`/`[✓]`/`[x]`/`[!]` message, and the
  full `cas help [topic]` text.
