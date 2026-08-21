<!-- &desc: "FIXED + VERIFIED: bruteforceLockout bypassable via parallel open attempts. Root fix + a self-deadlock regression it introduced are both resolved; 30-parallel-attempt repro confirmed correct." -->
# `bruteforceLockout` completely bypassable via parallel `open` attempts

## STATUS: FIXED AND VERIFIED (2026-08-21)

## Severity: CRITICAL

## Repro (confirmed empirically, pre-fix source)
```
cas tc create --size 200 --pass correcthorsebatterystaple
cas tc settings security bruteforceLockout enable --threshold 3 --pass correcthorsebatterystaple
for round in 1 2 3 4 5; do
  for i in 1 2 3 4 5 6; do
    cas tc open --pass "wrongpass${round}${i}" > "out-${round}-${i}.log" 2>&1 &
  done
done
wait
```
Pre-fix result: vault survived all 30 genuinely-wrong parallel attempts — concurrent
attempts raced on the LUKS mapper device name and never reached `check_lockout`.

## Root cause
`src/commands/open.rs::run()` had zero locking around the open sequence, so
concurrent `cas open` processes raced to set up the same LUKS mapper device,
each failing before `check_lockout` was ever reached.

## Fix (this session, 2026-08-21)
`Vault::lock_exclusive()` (`src/vault.rs`) is called by `src/cli.rs` before
dispatching to any vault-mutating command (`create`, `open`, `rename`,
`close`, `toggle`, `auth`, `backup`, `settings`, `exec`, `delete`, `resize`),
serializing all of them per-vault via a blocking `flock`.

## Regression found and fixed during this session's verification
The lock as last written had two bugs, both self-deadlocks, both fixed:

1. **Locking the `.img` file itself deadlocked against cryptsetup's own
   internal locking.** cryptsetup takes its own `flock(LOCK_EX)` directly on
   the vault image for `luksFormat`/`open`/etc (no `losetup` layer for these
   calls). Holding our own `flock` on that same file across a shelled-out
   `cryptsetup` call self-deadlocked every command that both locks and
   invokes cryptsetup. Confirmed live via `strace`: our process held the
   lock, `cryptsetup luksFormat` blocked forever on the same inode via a
   different fd. **Fix**: `lock_exclusive()` now locks a sibling
   `<name>.img.lock` file instead of the `.img` itself, which cryptsetup
   never touches.
2. **`src/commands/open.rs::run()` re-acquired the same lock a second time**
   inside a function already called with the lock held by `cli.rs`. A second
   `flock` from the same process on a second fd of the same lock file
   deadlocks against the first (also confirmed live via `strace`). **Fix**:
   removed the redundant inner lock; `open.rs::run()` now relies entirely on
   the caller's lock.

`src/commands/create.rs`'s exists-check was also simplified back to a plain
`vault.img.exists()` — the sibling-lock-file change means `create` no longer
needs a 0-byte image placeholder to close its own TOCTOU race.

## Verification (2026-08-21, foreground + parallel, this session)
- Serial regression check: 3 sequential wrong-passphrase attempts against a
  fresh `threshold=3` vault correctly showed `(1/3)`, `(2/3)`, then deletion
  on the 3rd — each attempt ~4s (uncontended `flock` acquire is cheap, no
  added latency).
- **30-parallel-attempt repro re-run against the fixed binary**: exactly one
  attempt landed each of `(1/3)`, `(2/3)`, and the delete message; the other
  27 (queued behind the lock, vault already gone by their turn) each got a
  single clean failure, no double-deletes, no silent bypass.

## New, separate, low-severity finding from this verification pass
Of the 27 post-deletion attempts above, each printed `[cas] opening 'tc' ...`
followed by a raw `No such file or directory (os error 2)` rather than a
clean "vault not found" message. `open.rs::run()` doesn't re-check
`vault.img.exists()` after acquiring the lock before calling
`Meta::read_versioned`/`get_secret`, so a vault deleted by a concurrent
`bruteforceLockout` trigger (or a concurrent `delete`) surfaces a raw OS
error to the next queued `open` instead of a clean message. Not a security
bug (no bypass, no double-delete) — cosmetic/UX only. Not fixed this
session; worth a follow-up `if !vault.img.exists() { die!(...) }` early in
`open.rs::run()` after the lock is acquired.
