# sudo broker — known bugs (2026-07-05)

Found while testing the new keyfile-based sudo auth (`Nixos/modules/security/sudo-keyfile.nix`).
The wrapper is unwired for now (`Nixos/home/apps.nix`'s `home.file.".local/bin/sudo"` is commented out) until these are fixed.

## 1. Bare maintenance flags (`-k`, likely `-K`, `-v`, `-l` too) break in non-TTY context

In `sudo`'s default case (the `*)` branch, non-interactive calls without an
active auto-mode session fall through to:

```bash
if _nopasswd_out=$("$REAL_SUDO" -n "$@" 2>&1); then
```

This unconditionally prepends `-n` to whatever args were given. For a normal
command (`sudo apt install htop`) that's fine — `sudo -n apt install htop` is
valid. But for a bare flag like `sudo -k` (reset the cached timestamp, no
command at all), the result is `sudo -n -k`, which real sudo can't parse as
any single valid mode and rejects with its own multi-line usage synopsis
instead of doing anything:

```
usage: sudo -h | -K | -k | -V
usage: sudo -v [-ABkNnS] [-g group] [-h host] [-p prompt] [-u user]
...
```

So `sudo -k` from a non-interactive caller (anything without a TTY — e.g. an
AI agent's shell tool) silently fails to reset the timestamp: no error is
surfaced as "your -k didn't work", it just prints sudo's generic usage text
and returns whatever exit code that produces. Confirmed live — this is not
theoretical.

**Fix direction**: special-case bare single-flag invocations (`-k`, `-K`,
`-v`, `-l` with no trailing command) the same way `-n` is already
special-cased a few lines above (`for _arg in "$@"; do [[ "$_arg" == "-n" ]]
&& exec "$REAL_SUDO" "$@"; done`) — pass them straight through to
`$REAL_SUDO` unmodified rather than through the `-n`-prepending NOPASSWD
preflight path.

## 2. The broker is not a real security boundary against direct binary calls

Not a code bug, more a design gap worth documenting since it came up directly:
`~/.local/bin/sudo` only works because it's earlier in `$PATH` than the real
`sudo` (`/run/wrappers/bin/sudo`). Anything that calls the real binary path
directly — `/run/wrappers/bin/sudo <cmd>` — skips the wrapper, and therefore
the broker's human-approval gate, entirely. This was already true before the
keyfile work; the keyfile change just makes such a bypass require *zero*
credentials at all instead of a password, which is what actually surfaced it
during testing (confirmed live: `timeout 3 /run/wrappers/bin/sudo id
< /dev/null` returned `uid=0(root)` instantly, no approval, no password, no
TTY).

If the broker is meant to be a hard gate rather than a `$PATH`-order
convenience, it'd need something that can't be routed around by construction
(e.g. NixOS's own `security.wrappers` mechanism pointed *at* the broker
script instead of at real sudo, or a PAM rule that itself invokes the broker
logic) — a real architecture change, not a quick fix.
