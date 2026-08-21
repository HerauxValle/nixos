<!-- &desc: "Worked end-to-end usage examples: first vault, 2FA on a removable drive, keyfile embedding, scripted/non-interactive use, and routine snapshot/settings workflows." -->
# Usage examples

## First vault

```sh
cas myvault create                 # 1 GiB, prompts for a passphrase
cas myvault open                   # unlocks + mounts at ./myvault
cp -r ~/Documents/taxes myvault/
cas myvault close                  # locks it again
```

## A vault with 2FA on a USB drive

```sh
cas myvault create --size 4G --strength hard
cas myvault settings 2fa enable    # writes myvault.key next to myvault.img
cas myvault auth keyfile move /run/media/$USER/MyKeys/vaults/
cas myvault open                   # cas auto-mounts MyKeys if it's plugged
                                    # in but not mounted, and unmounts it
                                    # again after — see keyfile_mount.rs
```

If the drive isn't plugged in, `open` prints a warning and falls back to
prompting as if 2FA weren't set — it won't unlock without the keyfile,
but it also won't hang waiting for a drive that isn't coming.

## Camouflaging a keyfile inside an ordinary-looking file

```sh
cas myvault settings 2fa enable
cas myvault auth keyfile embed ~/Pictures/holiday.jpg   # copy, doesn't switch yet
cas myvault auth keyfile activate ~/Pictures/holiday.jpg --pass "..."
                                    # verifies it actually unlocks the vault
                                    # before committing, then switches to it
cas myvault open                   # opens using holiday.jpg as the keyfile;
                                    # the photo itself is untouched
```

If the original raw `myvault.key` is ever lost but you still have the
photo, recover it with:

```sh
cas myvault auth keyfile extract ~/Pictures/holiday.jpg
```

And to reverse the camouflage entirely (only once the *raw* keyfile is
active again — `strip`ping the active one is refused without typing the
vault name to confirm, since it'd remove the only copy cas knows about):

```sh
cas myvault auth keyfile strip ~/Pictures/holiday.jpg
```

## Scripted / non-interactive use

Prefer piping the passphrase over stdin rather than `--pass` — `--pass`
ends up in shell history, and `cas` warns about that every time:

```sh
printf %s "$PASSPHRASE" | cas myvault open --no-log
```

`--no-log` suppresses all `[i]`/`[✓]` output; the exit code (0 on
success, 1 on failure) is still meaningful for scripting. `--no-confirm`
additionally skips the "type the vault name to confirm" prompts on
`delete`/`resize <smaller size>`/`backup restore`/`auth keyfile strip`
(when active) — combine both for a fully unattended destructive
operation.

## Routine snapshots

```sh
cas myvault settings backup auto enable --keep 5   # vault must be closed
cas myvault open                                    # snapshots automatically from here on
cas myvault backup list                             # see manual + auto snapshots
cas myvault backup create before-migration
cas myvault backup restore before-migration         # asks to confirm first
```

## Encryption-bypass UX (trusted machines only)

```sh
cas myvault settings encryption disable --pass "..."
cas myvault open                          # no prompt from here on
```

This stores the LUKS secret (hashed with your keyfile, if 2FA is on) in
the vault's own metadata trailer. It does **not** weaken the on-disk
encryption — the data is exactly as protected as before — but anyone
with read access to the `.img` file can now unlock it without your
passphrase. Only use this if the file itself lives somewhere already
trusted (e.g. inside another encrypted volume).

## Locking snapshots against a same-user attacker (ransomware)

```sh
cas myvault settings security ransomwareProtection enable --pass "..."
```

Locks `.casket/` (snapshots, and anything else cas keeps inside the
vault) to root-only, so your own user account — and anything running as
it, including ransomware — can no longer read, create, or delete
anything in there. It only stops a same-user attacker; root or raw
access to the vault's underlying block device is outside what this can
prevent.

By default, changing this setting (and `settings backup auto`) requires
re-proving the passphrase, so plain `sudo` access alone can't defeat it.
Turn that requirement off per-feature, or entirely, via:

```sh
cas myvault settings verification ransomwareProtection disable --pass "..."
```

## Checking what's around

```sh
cas list                 # vaults in cwd + 4 parent dirs, plus anything
                          # currently open anywhere on the machine
cas quit                 # equivalent to `cas all close`
```
