# Dotfiles

My NixOS system, flake-managed and fully reproducible. `nixos-rebuild switch` is the only install step that matters -- everything else in here is symlinked, generated, or scripted into place from this repo.

```
sudo ln -s ~/Dotfiles /etc/nixos   # (or just run ./install.sh --setup)
nixos-rebuild switch --flake /etc/nixos#herauxvalle
```

## Live-install ISO (no NixOS needed)

Anyone with the [Nix package manager](https://nixos.org/download) installed (flakes enabled, `x86_64-linux`) can build the live-install ISO straight from this repo -- no NixOS, no personal config, no account needed:

```
git clone https://github.com/HerauxValle/nixos.git
cd nixos
export ISO_DOTFILES_SOURCE="$PWD"   # the ISO embeds a snapshot of this exact clone at /dotfiles
nix build --impure --extra-experimental-features 'nix-command flakes' \
  '.#nixosConfigurations.maxmustermann-iso.config.system.build.isoImage'
```

The built `.iso` lands under `result/iso/`. Boot it (USB, VM) to try the desktop live or run the installer.

## Layout

| Path | What lives there |
|---|---|
| `Nixos/` | System + home-manager config -- `configuration.nix`, `home.nix`, `modules/` |
| `Hyprland/` | Window manager config (Hyprlang + a Lua layer) |
| `Quickshell/MyBar/` | Custom status bar & shell, Nix-packaged, C++ backend + QML |
| `Scripts/` | `pacnix` (rebuild wrapper), `Sudo` (broker), `Secrets`, `Backup`, `Wallpaper`, ... |
| `Kitty/`, `Fastfetch/`, `Themes/`, `Shells/` | The usual dotfiles suspects |
| `Backup/` | Snapshots of live, non-Nix-manageable app state (see `Scripts/Backup/backup.sh`) |
| `Documentation/` | `Bugfixes/` and `Features/` writeups worth keeping around |

## A few things worth knowing

- **`pacnix rebuild`** is the day-to-day command, not raw `nixos-rebuild`.
- **Passwordless sudo** while a keyfile USB (`VirtualKeys`) is plugged in -- see `Nixos/modules/security/sudo-keyfile.nix`.
- **MyBar** lives under `~/.config/quickshell` as a Nix-store symlink -- edits need a rebuild to go live.
- `install.sh --setup` is safe to re-run; it only symlinks `/etc/nixos` and seeds the initial password. `install.sh --format` is separate and destructive -- see `Installation/format.sh` -- for partitioning a blank disk via disko on a genuinely fresh install.

Tuned for my machine (hostname, hardware, keyfile paths), but nothing's hardcoded beyond config and variables -- fork it and swap those to make it yours.
