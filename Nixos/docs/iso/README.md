<!-- &desc: "Live-install ISO docs index -- what it is, why it exists, and where each design/implementation/bug/verification detail actually lives." -->

# Live-install ISO

This covers `nixosConfigurations.herauxvalle-iso` (`../../iso.nix`, wired
into `../../../flake.nix`), the `pacnix release`/`pacnix install`
commands that build and use it, and everything decided along the way.
Written up in detail because most of it came from a single long design
conversation plus real, repeated build failures -- worth keeping the
reasoning attached, not just the final files.

## Why this exists

Wanted a portable, live-bootable NixOS install medium built from this
same flake -- something a friend could boot, get the real Hyprland/
MyBar desktop, and actually install from. The naive version (bake in
literally everything on the real machine) measured at **35 GiB**
uncompressed closure, dominated by Steam+Swift (~20 GiB) and the
self-hosted services module (~13 GiB, mostly ComfyUI's CUDA stack) --
none of which need to be pre-loaded onto install media, since they'd
build/download normally on first `nixos-rebuild switch` after a real
install anyway. Final result: **4.3 GiB**, confirmed via a real build,
not an estimate.

## Continuing this in a new session?

Read **[handoff.md](handoff.md)** first -- exact current state, what's
built vs. stale, and the immediate next steps in order. This README is
background; that file is "start here."

## Where things are

- **[handoff.md](handoff.md)** -- current state and next steps, read
  this first if picking the work back up.
- **[design-decisions.md](design-decisions.md)** -- the override-list
  mechanism, why it doesn't touch `replacements.nix`, the `builtIn`
  allowlist model for packages, why SDDM/login is deliberately left
  untouched, the `pacnix release`/`install` naming.
- **[implementation.md](implementation.md)** -- every file touched or
  created, and what each one actually does.
- **[bugs-and-fixes.md](bugs-and-fixes.md)** -- every real build/eval
  failure hit getting this working, root cause and fix for each.
- **[verification-status.md](verification-status.md)** -- what's
  actually been confirmed end-to-end vs. what's still untested.
- **[usage.md](usage.md)** -- how to actually run `pacnix release` and
  `pacnix install`, and what to expect.

## The one-paragraph version

`nixosConfigurations.herauxvalle-iso` reuses the real modules/config
tree (same Hyprland, same MyBar, same everything) minus
`hardware-configuration.nix`/`partitioning.nix` (both pinned to this
exact physical disk), plus nixpkgs's own installer-cd base module and
one new override file (`iso.nix`) that forces off everything that's
either disk-specific (GRUB, the USB-keyfile LUKS unlock, personal
drive mounts) or just unnecessary weight for live media (self-hosted
services, Steam, and -- via a separate allowlist mechanism -- the
~100-entry personal package list). `pacnix release` builds it from the
already-redacted GitHub-published copy of the repo (reusing the exact
clone/attribute-resolution recipe `pacnix published` already used),
and embeds that same redacted clone onto the ISO at `/dotfiles` so
`pacnix install`, run from the booted live environment, can format a
disk and `nixos-install` fully offline.
