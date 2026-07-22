<!-- &desc: "Session handoff -- exact current state of the live-ISO work as of the session that wrote it, so a fresh chat can continue without re-establishing all the context. Read this first, then the other files in this directory as needed." -->

# Handoff -- read this first in a new session

Written specifically so a new chat can pick this up without the prior
session's full context. Everything referenced here is explained in more
depth in this directory's other files -- this one is just "where things
stand and what's next."

## Where things stand right now

- All code/design work described in `README.md`/`design-decisions.md`/
  `implementation.md` is done and pushed. `pacnix check` and `pacnix
  published` both pass (real config + `-iso` config, against the actual
  GitHub-published copy).
- **No `.iso` file currently exists anywhere** -- the last built one
  (4.6 GiB) was deleted, and `git`/`neovim` were added to the `builtIn`
  allowlist *after* that build, so it's stale regardless. **Next action
  is a fresh `pacnix rebuild` (to push the git/neovim addition) followed
  by `pacnix release`** to get a current ISO -- not yet done as of this
  writing.
- Confirmed acceptable size range: anything under ~5 GiB is genuinely
  fine for a live/install medium (comparable to Ubuntu Desktop/Manjaro
  ISOs) -- not a concern to optimize further unless it grows
  significantly past that.

## Packages currently opted into the ISO (`builtIn = true` in
`Nixos/config/software/packages/packages.nix`)

`vivaldi`, `git`, `neovim`, `fish`, `quickshell`, `fastfetch`, `tree`,
`awww`, `mybarBackend`, `kittyWrapped`, `ltree`, `cas`, `dolphin`,
`kio-extras`, `kio-admin`, `kservice`, `breeze`, `breeze-icons`,
`qtstyleplugin-kvantum`, `qt6ct`. Grep `packages.nix` for `builtIn` to
get the live, authoritative list -- this one will drift out of date the
moment anyone edits it again, don't trust this list over the file
itself.

Deliberately *not* included: `qt5ct` (nothing on the ISO is Qt5-
specific, everything KDE-ish here is Qt6 via the `qt6ct` theming
wiring) -- worth revisiting if that assumption turns out wrong once
actually booted.

## Immediate next steps, in order

1. `pacnix rebuild` (pushes the `git`/`neovim` `builtIn` additions to
   the published copy `pacnix release` builds from).
2. `pacnix release` (from wherever you want the `.iso` -- it lands in
   `$PWD`). Sanity-check the resulting size, delete the leftover `/nix/
   store/*.iso` build path afterward the same way this session did
   (`nix store delete <path>` -- the `pacnix release` copy in the target
   dir is independent, deleting the store original is safe).
3. **VM rehearsal of `pacnix install`** -- this has never been run, not
   even once. See `verification-status.md`'s "Before this ever touches
   real hardware" section for the exact discipline to follow (matches
   `../disko-wiring-verification.md`/`../../../Installation/doc.md`'s
   existing approach: spare virtual disk, boot the real built ISO,
   reboot into the *installed* disk afterward, not the installer's own).
   This is the one thing standing between "looks right on paper" and
   "actually works."
4. Only after the VM rehearsal passes: an actual live boot on real
   hardware, per the user's stated plan.

## Open questions / things flagged but not resolved

- Whether Hyprland/SDDM actually come up on a real boot at all --
  reasoned to be fine (nothing disables them, `programs.hyprland.enable`
  untouched), never observed.
- Whether the current `builtIn` package set is actually sufficient for
  a comfortable install session, or whether something obvious is
  missing -- won't really be known until someone's actually driving the
  live session by hand.

## Quick reference

- `pacnix check` -- fast eval-only sanity check, run this after any
  `.nix` edit before anything heavier.
- `pacnix published` -- dry-builds both flake attributes against the
  real pushed repo.
- `pacnix release` -- builds the actual `.iso` from that pushed repo.
- `pacnix install` -- run *inside the booted ISO* to actually
  format+install (untested, see above).
- Key files: `../../iso.nix` (override list), `../../../flake.nix`
  (the `-iso` output), `Nixos/config/software/packages/packages.nix`
  (where `builtIn` gets set per package), `Scripts/Pacnix/cmd/
  {release,install,published}.sh`.
- The rest of this directory, in the order worth reading: `README.md`
  -> `design-decisions.md` -> `implementation.md` -> `bugs-and-fixes.md`
  -> `verification-status.md` -> `usage.md`.
