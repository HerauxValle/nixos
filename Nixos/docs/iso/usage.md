<!-- &desc: "How to actually run pacnix release and pacnix install, what each does, and where output lands." -->

# Usage

## Building the ISO: `pacnix release`

```sh
cd ~/wherever-you-want-the-iso
pacnix release
```

What it does:
1. Reads `config.vars.backup.dotfilesBackup.remoteUrl`/`.branch` off
   the local flake, converts the SSH remote to HTTPS, and clones it
   fresh into a temp dir -- the same *published* copy `pacnix
   published` validates, already redacted by `Nixos/config/github/
   {redactions,replacements}.nix` (personal username/hostname/security
   posture reset, see `design-decisions.md`).
2. Resolves the live-ISO flake attribute from that clone (handles
   `replaceValues` having renamed it to a placeholder).
3. Builds `.config.system.build.isoImage` from the clone, with
   `ISO_DOTFILES_SOURCE` pointed at that same clone -- so the ISO
   embeds a snapshot of the exact redacted copy it was built from.
4. Copies the resulting `.iso` into whatever directory you ran `pacnix
   release` from, prints its path and size, cleans up the temp clone.

**Always run this from the directory you actually want the `.iso` file
in** -- it lands wherever `$PWD` was at invocation, not a fixed
location.

Since it builds from the *published* GitHub copy, not your local
checkout, **push first** (`pacnix rebuild` already does this as part of
its normal flow) if you've made changes you want reflected in the ISO.

## Using the ISO: `pacnix install`

Run from *inside the booted live ISO*, not from the real machine:

```sh
export DISKO_ROOT_KEYFILE=/path/to/a/keyfile   # same requirement as running
                                                 # install.sh --format directly
pacnix install
```

What it does:
1. Runs the embedded `/dotfiles/install.sh --format` unmodified --
   every existing prompt stays exactly as it is (pick a disk from
   `by-id`, retype the *resolved* path back, type `WIPE` in caps to
   confirm). Wipes and partitions/formats the chosen disk via disko,
   mounts it under `/mnt`.
2. Resolves the real (non-`-iso`) flake attribute from `/dotfiles` the
   same way `release.sh` does, then runs `nixos-install --root /mnt
   --flake /dotfiles#<attr>` -- installing the *full* real config
   (Hyprland, MyBar, everything), not the trimmed live-ISO one. The
   ISO's own trimming (self-hosted services off, `builtIn`-gated
   packages) only ever affected what's running on the boot medium
   itself.
3. Prints the same "reboot, then run `./install.sh --setup`"
   instructions `format.sh` already prints when run directly -- that
   step inherently runs post-reboot on the newly-installed system, so
   it stays a separate, manual step.

See `verification-status.md`: this command has not actually been run
yet as of this writing. Read that file before pointing it at real
hardware.

## Adding packages to the live environment

Nothing from the personal package list ships on the ISO by default
(see `design-decisions.md`'s `builtIn` section). To add one, edit its
entry in `Nixos/config/software/packages/packages.nix`:

```nix
config.vars.packages.environment.packages.pkgs.firefox = {
  builtIn = true;
};
```

Then rebuild the published copy (`pacnix rebuild`) before the next
`pacnix release`, since `release.sh` always builds from the published
clone, not the local checkout.
