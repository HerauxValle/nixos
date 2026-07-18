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
| `--new-pass "..."` | New passphrase, for `passwd` only. |
| `--keyfile path` | 2FA keyfile path override, for `open`/`toggle`. |
| `--size MiB` | Vault size for `create` (default 1024). |
| `--strength level` | `light` / `medium` (default) / `hard` / `extreme`. |
| `--path dir` | Look for vaults here instead of searching cwd + 4 parent directories. |
| `--no-log` | Suppress all output — for scripts. |
| `--no-confirm` | Skip "type the vault name to confirm" prompts. |

## Actions

| Action | Requires vault state | Notes |
|---|---|---|
| `create` | must not exist | prompts for size/passphrase if not given |
| `open` | closed | formats on first use, handles 2FA/encryption-bypass |
| `close` | open | |
| `toggle` | any | open↔close; skips the shell-history warning `open` prints |
| `info` | any | size, open state, 2FA status, active slot count |
| `passwd` | closed | safe two-phase rekey, see `docs/architecture.md` |
| `2fa on` / `2fa off` | closed | generates/removes `<name>.key` |
| `encryption on` / `off` | closed | toggles the no-prompt-on-open bypass |
| `backup create <name>` | open | readonly btrfs snapshot |
| `backup list` | open | manual + auto snapshots, newest first |
| `backup restore <name>` | open | replaces current contents; asks to confirm |
| `backup delete <name>` | open | |
| `backup auto enable [--keep N]` | closed | snapshot on every future `open` |
| `backup auto disable` | closed | existing auto-snapshots are kept |
| `backup auto keep <N>` | closed | |
| `resize <size>` (alias `shrink`) | closed | grow is instant; shrink checks used space first |
| `rename <newname>` | closed | |
| `delete` | closed | asks to confirm |
| `list` | — | global; also shows vaults open from elsewhere via `/proc/mounts` |
| `all close` / `quit` | — | global; closes every open vault on the machine |

`cas path/to/vault.img` (a single argument ending in `.img` or containing
a path separator) is shorthand for `toggle` on that vault.

Every action above also has a longer page with examples: `cas help
<action>` (e.g. `cas help resize`).
