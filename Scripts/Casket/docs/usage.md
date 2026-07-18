<!-- &desc: "Worked end-to-end usage examples: first vault, 2FA on a removable drive, scripted/non-interactive use, and routine snapshot workflows." -->
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
cas myvault 2fa on                 # writes myvault.key next to myvault.img
mv myvault.key /run/media/$USER/MyKeys/vaults/
cas myvault open                   # cas auto-mounts MyKeys if it's plugged
                                    # in but not mounted, and unmounts it
                                    # again after — see keyfile_mount.rs
```

If the drive isn't plugged in, `open` prints a warning and falls back to
prompting as if 2FA weren't set — it won't unlock without the keyfile,
but it also won't hang waiting for a drive that isn't coming.

## Scripted / non-interactive use

Prefer piping the passphrase over stdin rather than `--pass` — `--pass`
ends up in shell history, and `cas` warns about that every time:

```sh
printf %s "$PASSPHRASE" | cas myvault open --no-log
```

`--no-log` suppresses all `[i]`/`[✓]` output; the exit code (0 on
success, 1 on failure) is still meaningful for scripting. `--no-confirm`
additionally skips the "type the vault name to confirm" prompts on
`delete`/`resize <smaller size>`/`backup restore` — combine both for a
fully unattended destructive operation.

## Routine snapshots

```sh
cas myvault backup auto enable --keep 5   # vault must be closed
cas myvault open                          # snapshots automatically from here on
cas myvault backup list                   # see manual + auto snapshots
cas myvault backup create before-migration
cas myvault backup restore before-migration  # asks to confirm first
```

## Encryption-bypass UX (trusted machines only)

```sh
cas myvault encryption off --pass "..."
cas myvault open                          # no prompt from here on
```

This stores the LUKS secret (hashed with your keyfile, if 2FA is on) in
the vault's own metadata trailer. It does **not** weaken the on-disk
encryption — the data is exactly as protected as before — but anyone
with read access to the `.img` file can now unlock it without your
passphrase. Only use this if the file itself lives somewhere already
trusted (e.g. inside another encrypted volume).

## Checking what's around

```sh
cas list                 # vaults in cwd + 4 parent dirs, plus anything
                          # currently open anywhere on the machine
cas quit                 # equivalent to `cas all close`
```
