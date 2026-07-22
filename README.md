# Dotfiles

> [!WARNING]
> If you build or install from this repo without the real password hash file present (`/etc/nixos-secrets/`), account setup silently falls back to a known hash for the password **`changeme`** (`Nixos/modules/system/users/users.nix`) instead of failing. This applies to `install.sh --format`/`--setup` and any fresh live-ISO install. Run `secrets passwd` immediately after first boot to set a real one, then rebuild.

My NixOS system, flake-managed and fully reproducible. `nixos-rebuild switch` is the only install step that matters -- everything else in here is symlinked, generated, or scripted into place from this repo.

```
sudo ln -s ~/Dotfiles /etc/nixos   # (or just run ./install.sh --setup)
nixos-rebuild switch --flake /etc/nixos#herauxvalle
```

## Live-install ISO (no NixOS needed)

Anyone with the [Nix package manager](https://nixos.org/download) installed (flakes enabled, `x86_64-linux`) can build the live-install ISO -- no NixOS, no personal config, no account, no prior clone needed:

```
curl -fsSL https://raw.githubusercontent.com/HerauxValle/nixos/main/install.sh | bash -s -- --build-iso
```

Clones the repo into a tmp dir, builds, and drops the finished `.iso` in `~/Downloads`. (Already have this repo cloned? `./install.sh --build-iso` does the same thing.)

## What's actually in here

### `pacnix` -- day-to-day CLI (`Scripts/Pacnix/`)

```
pacnix rebuild [--label <text>]   sudo nixos-rebuild switch
pacnix validate                    dry-build, no switch
pacnix check                       nix flake check, fast eval-only
pacnix test-build                  full build, no switch, no sudo
pacnix published                   dry-builds the actual redacted GitHub copy, not the local checkout
pacnix release                     builds the live-install ISO from the published copy
pacnix install                     run inside the booted ISO -- format + nixos-install
pacnix optimise / orphaned / store store housekeeping (dedup, GC, size)
pacnix packages / plugins / modules / logs / info   introspection
```

`published` exists specifically to catch what `test-build` structurally can't: a redaction/replacement entry that leaves the *published* copy broken while the local flake (which still has every real value) builds fine.

### Hyprland (`Hyprland/`)

Config is Lua, not raw Hyprlang -- `hyprland.lua` is the entry point, `require()`-ing one file per concern in numbered sections: `Config.Core.{env,monitors,input}`, `Config.UI.{theme,workspaces}`, `Config.Rules.{layout,rules}`, `Config.Apps.{defaults,autostart}`, `Config.Binds.{apps,binds,laptop,media,system,plugins}`, `Config.Plugins.{easymotion,hyprexpo,borders-plus-plus,hyprwinwrap}`. Plugins themselves are built from git via `vars.hyprland.hyprlandPlugins` (name/url/rev/hash), loaded the same way home-manager's own plugin wiring would, no `hyprpm` involved. Animation/gap tuning is deliberate, not defaults -- see `Documentation/Features/hyprland-kitty-motion-tuning.md`.

### MyBar (`Quickshell/MyBar/`)

Custom status bar/shell replacing waybar/eww, C++ backend + QML, Nix-packaged. Lives at `~/.config/quickshell` as a Nix-store symlink -- edits need a rebuild. Icons are `Symbols Nerd Font Mono` glyphs (`fonts.packages` in `Nixos/modules/desktop/theming.nix`), not an icon theme -- missing that font renders every icon as a tofu box.

### `cas` -- Casket vault manager (`Scripts/Casket/`, Rust)

Per its own Cargo manifest: "Encrypted vault manager -- LUKS2 image files with optional 2FA keyfile, btrfs snapshots, and safe passphrase rotation." Subcommands: `create`, `open`, `close`, `delete`, `rename`, `backup`, `shrink`, `passwd`, `encryption`, `toggle`, `info`.

### `gitctl` -- git push-target registry (`Nixos/modules/packages/repos/`)

```
gitctl push <name>                 squash-push a registered repo to its remote
gitctl release <name> <tag> [changelog]   push + tag + a real GitHub Release
gitctl release rm <name> <tag>     delete both
```

Registry is declared in `config.vars.packages.repos.repos`, each entry naming a local path + remote + (optionally) a `githubRepo` for `release`. Its own exclude mechanism (`excludePaths`/`excludeFiles`) is deliberately simpler than -- and separate from -- the dotfiles-backup redaction pipeline below; don't point it at a path containing secrets expecting the same scrubbing.

### `secrets` / `ltree` (`Scripts/Secrets/`, `Scripts/LTree/`)

`secrets <dotfiles|github|passwd|qbittorrent|self-hosted>` rotates root-owned credentials outside the repo (deploy keys, PATs, password hashes). `lt` is the directory-explorer this README's own line counts came from (`lt <dir> -L 99 -o TOTAL`, `-e` to exclude build noise).

### Dotfiles backup/publish (`Nixos/modules/backup/dotfiles/`)

Every `pacnix rebuild` pushes a redacted snapshot of this exact config to GitHub -- username, hostname, MAC, keyfile paths swapped for placeholders per `Nixos/config/github/{exclusions,redactions,replacements}.nix`. This README is that published copy, not a hand-maintained mirror. Auth is an SSH deploy key (`secrets dotfiles`), repo-scoped, push-only -- it cannot create GitHub Releases (that needs the separate `classic` PAT kind, `secrets github add classic`, which `gitctl release` uses instead).

### Sudo via keyfile (`Nixos/modules/security/sudo-keyfile/`)

A setuid-root PAM checker wired into `security.wrappers` + `system.activationScripts`. Passwordless while a specific USB keyfile drive is mounted, real password otherwise.

### Live-install ISO (`Nixos/iso.nix`, `Installation/build-iso.sh`)

Built from the same redacted published copy as `pacnix release`, embeds a snapshot of itself at `/dotfiles` for a fully offline `install.sh --format`. `vars.isoBuild = true` flips the package list into allowlist mode -- nothing from `vars.packages.environment.packages` ships on the ISO unless it opts in with `builtIn = true`.

### Self-hosted services (`Nixos/modules/services/self-hosted/`)

Ollama, ComfyUI, OpenWebUI, Immich, Jellyfin, Stash, SearXNG, Filebrowser, qBittorrent, Odysseus, plus an ACL-traversal helper -- each its own module with a real enable switch, each with a companion `glossar/self-hosted/<name>.nix` reference and `info.md`.

## Configuration (`config.vars.*`)

Every custom option this repo defines lives under one `config.vars` tree (verified against the live-evaluated option set, not just the docs below -- a couple of the glossar's own example comments had drifted from the real nesting). Schema (the `options.vars.*` declarations) and real per-machine values (`Nixos/config/config.nix` + siblings) are deliberately separate files, so a stranger forking this repo edits only the latter.

| Namespace | What it configures | Reference |
|---|---|---|
| `vars.identity` | Central facts -- username, homeDirectory, hostName, networkInterface, secretsBaseDir, stateVersion, timeZone, gitCommitEmail | `glossar/main/variables.nix` |
| `vars.backup.dotfilesBackup` | GitHub backup/publish -- redaction, tagging, push-on-rebuild | `glossar/main/variables.nix` |
| `vars.boot.grub` | GRUB theming | `glossar/main/variables.nix` |
| `vars.boot.luks2` | LUKS unlock via USB keyfile | `glossar/main/variables.nix` |
| `vars.boot.usbRequired` | USB-gated boot -- powers off if the key's missing | `glossar/main/variables.nix` |
| `vars.desktop.default` | Dolphin menu, udisks2, polkit, gvfs | -- |
| `vars.hyprland.hyprlandPlugins` | Hyprland plugins built from git (name/url/rev/hash) | `glossar/main/variables.nix` |
| `vars.packages.environment` | Declarative package installs -- sources, version pinning, flake inputs, ISO `builtIn` allowlist | `glossar/software/packages.nix` |
| `vars.packages.programs` | Program toggles (fish/hyprland/direnv/nix-ld) -- thin mirrors of native options, undocumented on purpose | -- |
| `vars.packages.repos` | `gitctl` push-target registry | `glossar/software/repos.nix` |
| `vars.packages.scripts` | PATH-exposed scripts (copies the containing folder so sibling files resolve) | `glossar/main/variables.nix` |
| `vars.packages.shells` | Declarative per-directory dev shells | `glossar/main/variables.nix` |
| `vars.packages.venvs` | Python venv registry/builder | `glossar/software/venvs.nix` |
| `vars.security.sudoKeyfile` | Passwordless sudo via USB keyfile | `glossar/main/variables.nix` |
| `vars.security.usbKillswitch` | Shutdown-on-USB-removal | `glossar/main/variables.nix` |
| `vars.services.selfHosted.*` | 10 self-hosted services + ACL-traversal helper | `glossar/self-hosted/*.nix`, one file per service |
| `vars.system.autostart` | Root-only systemd autostart jobs | `glossar/system/autostart.nix` |
| `vars.system.hiddenDevices` | Disk UUIDs hidden from udisks2 | -- |
| `vars.system.mountpoints` | Disk registry/manager (UUID required; LABEL/NAME need live disk access) | `glossar/system/mountpoints.nix` |
| `vars.system.ports` | Port-forwarding -- local/onion/router, independent and combinable | `glossar/system/port-forwarding.nix` |
| `vars.system.users` | Account password hash | -- |
| `vars.alias` | Shortcuts for deeply-nested vars.* paths you reference often | `Nixos/modules/alias.nix` |
| `vars.isoBuild` | Flips `vars.packages.environment.packages` into ISO allowlist mode | `Nixos/iso.nix` |

Every `glossar/*.nix` file is a real, copy-pasteable example -- every option for that module, commented out, never imported/evaluated. Copy a block into `Nixos/config/config.nix` (or the relevant sibling under `Nixos/config/`) and uncomment to actually set it.

## Layout

| Path | What lives there |
|---|---|
| `Nixos/` | System + home-manager config -- `configuration.nix`, `home.nix`, `iso.nix`, `modules/`, `config/`, `glossar/` |
| `Hyprland/` | Window manager config (Hyprlang + a Lua layer) |
| `Quickshell/MyBar/` | Custom status bar & shell, Nix-packaged, C++ backend + QML |
| `Scripts/` | `pacnix`, `Casket` (vault), `LTree` (`lt`), `Sudo` (broker), `Secrets`, `Backup`, `Wallpaper`, `Reload`, ... |
| `Themes/` | Kvantum, QT, Dolphin, GRUB, Gwenview, Searxng, Jellyfin |
| `Neovim/`, `Kitty/`, `Fastfetch/`, `Shells/`, `Mpv/` | The usual dotfiles suspects |
| `Python/` | Lockfiles for self-hosted services (ComfyUI, OpenWebUI, Odysseus, SearXNG, ...) |
| `Installation/` | `setup.sh`, `format.sh` (disko), `build-iso.sh` -- all dispatched through `install.sh` |
| `Backup/` | Snapshots of live, non-Nix-manageable app state (see `Scripts/Backup/backup.sh`) |
| `Documentation/` | `Bugfixes/` and `Features/` writeups worth keeping around |
| `Conventions.md`, `TODO.md`, `LICENSE` | Repo-level notes and the Apache 2.0 text |

## A few things worth knowing

- `pacnix rebuild` is the day-to-day command, not raw `nixos-rebuild`.
- Passwordless sudo while a keyfile USB (`VirtualKeys`) is plugged in -- see `Nixos/modules/security/sudo-keyfile/`.
- MyBar lives under `~/.config/quickshell` as a Nix-store symlink -- edits need a rebuild to go live.
- `install.sh --setup` is safe to re-run; it only symlinks `/etc/nixos` and seeds the initial password. `install.sh --format` is separate and destructive -- see `Installation/format.sh` -- for partitioning a blank disk via disko on a genuinely fresh install.
- `gitctl release`'s push step is not redaction-aware -- only ever point it at repos that don't need scrubbing. This repo's own GitHub copy goes out exclusively through the dotfiles-backup pipeline above, never through `gitctl`.

Tuned for my machine (hostname, hardware, keyfile paths), but nothing's hardcoded beyond config and variables -- fork it and swap those to make it yours.

## Line counts

`Nixos/`, `Quickshell/`, and `Hyprland/` via `lt <dir> -L 99 -o TOTAL`, build artifacts/caches/vendored binaries excluded:

| Directory | Lines | Files | Chars |
|---|---:|---:|---:|
| `Nixos/` | 27,185 | 333 | 1,216,406 |
| `Quickshell/` | 13,039 | 82 | 743,455 |
| `Hyprland/` | 1,642 | 37 | 68,357 |
