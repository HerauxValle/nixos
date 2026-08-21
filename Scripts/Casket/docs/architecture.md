<!-- &desc: "Module map and the design decisions behind cas's Rust rewrite: why no CLI-parsing crate, the stdin-secret pattern, and the meta-restoration guarantee." -->
# Architecture

`cas` is a single binary (`src/main.rs`) that self-elevates to root via
`sudo`, parses `argv`, and dispatches to one function per action under
`src/commands/`. Everything below that is plain synchronous code — no
async runtime, no thread pool. A CLI invocation runs one command and
exits; there's nothing here that benefits from concurrency, and pulling
in an executor would only add startup and binary-size cost.

## Module map

| Module | Owns |
|---|---|
| `config.rs` | Constants: mapper prefix, trailer magic, KDF presets |
| `error.rs` | `CasError` (`Msg` / `Silent`) and the `die!` macro |
| `ctx.rs` | `Ctx` (quiet/no_confirm) and the `logf!` macro |
| `meta.rs` | Trailing metadata block: read/strip/write |
| `secret.rs` | Passphrase+keyfile → LUKS secret derivation |
| `luks.rs` | Every `cryptsetup` invocation |
| `vault.rs` | Path resolution (`<name>.img`/mount dir/mapper) and mount-state checks |
| `keyfile_mount.rs` | Auto-mount/unmount a keyfile on a removable drive |
| `udisks.rs` | Loop devices, udev retriggers, real-user privilege drop |
| `btrfs.rs` | Filesystem label/resize/used-space, subvolume snapshot/delete |
| `size.rs` | `"20GiB"` ⇄ MiB conversions |
| `prompt.rs` | Interactive prompts and the `--pass`/stdin/prompt precedence chain |
| `proc.rs` | The four `std::process::Command` wrapper shapes everything else uses |
| `help.rs` | The hand-written help text |
| `cli.rs` | argv scanning and the vault/action dispatch |
| `commands/*.rs` | One file per action |

## Why no CLI-parsing crate

The grammar is `cas <vault> <action> [flags anywhere] [action args]` —
the subject comes before the verb, and flags can land anywhere in argv,
including after positional words (`cas myvault create --size 4096`).
clap's positional-argument model wants flags to stop once positional
collection starts (`trailing_var_arg`) or wants the flags-then-verb order
subcommands assume. Forcing either would have meant changing the
argument order users already have muscle memory (and shell aliases) for.
`cli.rs` instead ports the original's own `pop_opt()` scanner almost
verbatim — a dozen lines, no edge cases to reason about.

## Where the pluggability lives

Every action is `commands::<name>::run()` (or `::dispatch()` for actions
with their own sub-actions, like `backup` and `2fa`). Adding a new
top-level action is: a new file in `commands/`, one `pub mod` line in
`commands/mod.rs`, and one match arm in `cli.rs`'s `run()`. Nothing else
changes — each command owns its full argument contract instead of
conforming to one shared trait, which fits better here since `create`,
`resize`, and `close` genuinely take different arguments.

## The stdin-secret pattern

Every `cryptsetup` call that needs exactly one secret pipes it over
`--key-file -` (stdin) instead of writing it to a temp file first —
`proc::run_with_stdin` — so the secret never touches disk, not even
briefly. The one exception is `luksAddKey`, which needs *two* secrets
(the existing auth key and the new one) in a single invocation; since a
child process has only one stdin stream, that one case still uses two
temp files, but they're created with `O_CREAT|O_EXCL` and mode 0600 in a
single syscall (no separate `chmod` window) and deleted via `Drop`, so
cleanup happens even on an early `?` return.

## The meta-restoration guarantee

Every operation that calls `Meta::strip()` before touching the LUKS
container is structured so `Meta::write()` runs on *every* exit path —
success or `Result::Err` — before the function returns. `commands/open.rs`,
`passwd.rs`, `twofa.rs`, `encryption.rs`, and `resize.rs` all follow this
shape. This matters because the metadata trailer is where the 2FA keyfile
path, `backup_auto` settings, and the encryption-bypass autokey live —
losing it doesn't touch your data, but it does silently forget those
settings. `resize` in the original Python didn't guarantee this (a
`die()` during the shrink safety check left the trailer stripped for
good) — see `docs/porting-notes.md` for this and the other behavioral
fixes made during the port, and `docs/metadata-format.md` for the
trailer's on-disk layout.
