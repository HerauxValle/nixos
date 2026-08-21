<!-- &desc: "Structured command/flag reference for cas; `cas help <action>` gives the same information interactively with examples." -->
# CLI reference

```
cas <vault> <action> [options]
cas list
cas quit
cas all close
cas help <action>
```

Flags may appear anywhere in the command line, before or after the
vault/action words.

## Global flags

| Flag | Effect |
|---|---|
| `--pass "..."` | Passphrase. Prompted for if omitted. If the value is an existing file path, its contents (trimmed) are used instead. |
| `--new-pass "..."` | New passphrase, for `auth passwd` only. |
| `--keyfile path` | Keyfile path override — for `open`/`toggle`, and for `auth keyfile move/reset/embed` to say where the *current* keyfile actually is if the cached path is stale. |
| `--size MiB` | Vault size for `create` (default 1024). |
| `--strength level` | `light` / `medium` (default) / `hard` / `extreme`. |
| `--path dir` | Look for vaults here instead of searching cwd + 4 parent directories. |
| `--removeKeyfile` | `delete` only: also delete the 2FA keyfile (preserved by default — see below). |
| `--no-log` | Suppress all output — for scripts. |
| `--no-confirm` | Skip "type the vault name to confirm" prompts. |

## Actions

| Action | Requires vault state | Notes |
|---|---|---|
| `create` | must not exist | prompts for size/passphrase if not given |
| `open` | closed | formats on first use, handles 2FA/encryption-bypass, runs any pending schema migration |
| `close` | open | |
| `toggle` | any | open↔close; skips the shell-history warning `open` prints |
| `info` | any | size, open state, 2FA status, active slot count |
| `resize <size>` (alias `shrink`) | closed | grow is instant; shrink checks used space first |
| `rename <newname>` | closed | |
| `delete [--removeKeyfile]` | closed | asks to confirm; keyfile preserved unless `--removeKeyfile` is given, since it isn't necessarily exclusive to this vault |
| `list` | — | global; also shows vaults open from elsewhere via `/proc/mounts` |
| `all close` / `quit` | — | global; closes every open vault on the machine |

### `auth` — identity material (passphrase, keyfile)

| Action | Requires vault state | Notes |
|---|---|---|
| `auth passwd` | closed | safe two-phase rekey, see `docs/architecture.md` |
| `auth keyfile move <location>` | closed | relocates the active keyfile (copy, verify, delete original); preserves raw/embedded form |
| `auth keyfile reset [location]` | closed | overwrites with fresh key bytes, re-keys the LUKS slot to match; **irreversible** |
| `auth keyfile embed <carrier-file>` | any | copies the active keyfile's bytes into a trailer appended to any file, without disturbing its content |
| `auth keyfile extract <carrier-file> [location]` | any | recovery: pulls key bytes back out of an embedded carrier into a standalone raw file |
| `auth keyfile strip <carrier-file>` | any | opposite of `embed`; removes the trailer. Requires typed confirmation if the carrier is the active keyfile |
| `auth keyfile activate <location>` | closed | points the vault at a different keyfile file (raw or embedded); verifies it actually unlocks the vault first, never re-keys |

A keyfile is either **raw** (the whole file is the key — today's format,
unchanged) or **embedded** (key bytes in a small tagged trailer appended
to an otherwise-arbitrary carrier file, which keeps working as that
file). Which form a file is in is auto-detected everywhere a keyfile is
read; you never declare it.

### `backup` — snapshot data operations (not settings)

| Action | Requires vault state | Notes |
|---|---|---|
| `backup create <name>` | open | readonly btrfs snapshot |
| `backup list` | open | manual + auto snapshots, newest first |
| `backup restore <name>` | open | replaces current contents; asks to confirm |
| `backup delete <name>` | open | |

Snapshots live at `.casket/snapshots/<name>` inside the vault. The
auto-backup on/off *policy* is a setting, not a data operation — see
`settings backup auto` below.

### `settings` — every persistent per-vault toggle, all `enable|disable`

| Action | Requires vault state | Notes |
|---|---|---|
| `settings encryption enable\|disable` | closed | toggles the no-prompt-on-open bypass |
| `settings 2fa enable\|disable` | closed | generates/removes `<name>.key` |
| `settings backup auto enable [--keep N]` | closed | snapshot on every future `open` |
| `settings backup auto disable` | closed | existing auto-snapshots are kept |
| `settings backup auto keep <N>` | closed | |
| `settings security ransomwareProtection enable\|disable` | any | locks `.casket/` to root-only, blocking a same-user attacker (e.g. ransomware) from touching anything cas keeps inside the vault |
| `settings verification <feature> enable\|disable` | any | whether toggling `<feature>` requires re-proving the passphrase first; defaults on for `ransomwareProtection`/`backupAuto`/`verification`/`keyfileReset`, off for `encryption`/`2fa` (which already self-verify) |

`cas path/to/vault.img` (a single argument ending in `.img` or containing
a path separator) is shorthand for `toggle` on that vault.

Every action above also has a longer page with examples: `cas help
<action>` (e.g. `cas help auth`, `cas help settings`).
