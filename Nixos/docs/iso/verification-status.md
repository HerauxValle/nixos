<!-- &desc: "What's actually been confirmed end-to-end for the live ISO work vs. what's still untested -- read this before trusting any of it against real hardware." -->

# Verification status

## Confirmed, for real (not just evaluated)

- `pacnix check` -- both `nixosConfigurations.herauxvalle` and
  `nixosConfigurations.herauxvalle-iso` evaluate cleanly.
- `pacnix published` -- dry-builds both the real config and the `-iso`
  config's `isoImage` against the actual pushed GitHub repo, not just
  the local checkout. Passes.
- `pacnix release` -- actually built a real ISO from the redacted
  clone. Result: **4.3 GiB** (down from the 35 GiB naive-everything
  estimate).
- **Redaction is genuinely in effect inside the built artifact**,
  checked by extracting `/dotfiles/Nixos/config/config.nix` out of the
  actual built ISO with `xorriso` and reading it: `username =
  "maxmustermann"`, `hostName = "nixos"`, `usbRequired.enable = false`,
  `sudoKeyfile.enable = false`, `usbKillswitch` placeholders,
  `dotfilesBackup.enable = false`. Not assumed -- read back from the
  real file inside the real image.
- `config.vars.isoBuild` correctly `false` on the real machine, `true`
  only on `-iso`; self-hosted services/Steam correctly disabled only on
  `-iso` (`nix eval` against both configs directly).
- `environment.systemPackages` count: 308 (real machine) vs. 205 (ISO,
  base installer + Hyprland only, zero personal packages opted in via
  `builtIn` yet).
- The embedded `/dotfiles` is present and complete on the built ISO
  (`xorriso -find /dotfiles` lists the full tree, `flake.nix`/
  `install.sh` included).

## NOT yet tested

- **`pacnix install` itself has never been run.** Nothing has actually
  booted this ISO -- not in a VM, not on real hardware. The
  format.sh-orchestration logic, the dynamic attribute resolution
  against the embedded `/dotfiles`, and the `nixos-install --root /mnt
  --flake /dotfiles#<attr>` call are all unexercised beyond reading the
  code.
- **Whether the ISO actually boots into a working Hyprland/SilentSDDM
  session at all.** Login/session was deliberately left unmodified on
  the theory that it should just work the same as the real machine
  (see `design-decisions.md`) -- that's a reasoned bet, not a confirmed
  fact.
- **Whether disko's install flow behaves identically when driven from
  inside the *live ISO's own* environment** (as opposed to some other
  arbitrary NixOS installer, which is what `format.sh`/`partitioning.nix`
  were originally verified against per `../disko-wiring-verification.md`
  and `../../../Installation/doc.md`). The mechanism should be the
  same, but this specific combination hasn't been rehearsed.
- No package has been opted into `builtIn = true;` yet -- the live
  environment currently has no browser, no disk-management GUI, nothing
  beyond what the installer base module and Hyprland pull in by
  default. Untested whether that's actually enough to comfortably drive
  a real install from.

## Before this ever touches real hardware

A VM rehearsal, matching the discipline `../../../Installation/doc.md`
already used for the underlying disko mechanism (that file's own
record: 9 distinct bugs caught only by an actual install-and-boot
rehearsal, none of them find-able by evaluation alone). Concretely:
boot the built ISO in a NixOS test/QEMU VM with a spare virtual disk,
run `pacnix install` against it for real, reboot into the *installed*
disk (not the installer's own -- see that file's "Bug 4" for why a
naive second `machine.start()` doesn't do this), and confirm it comes
up. Not done as of this writing.
