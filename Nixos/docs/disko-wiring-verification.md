<!-- &desc: "Records what was actually verified (schema, fileSystems generation, LUKS merge, a full VM install-and-boot rehearsal) before partitioning.nix could be trusted, and the one known divergence from the live system." -->

# disko wiring verification

`../partitioning.nix` documents this machine's real disk layout and is
fully runnable, but is **not** imported into `nixosConfigurations.herauxvalle`
(see that file's own top comment for why). This records what was actually
verified before it could be trusted enough to consider wiring in for real,
and what's still open.

## What was checked, and how

1. **Schema validity** -- evaluated through disko's actual module system
   (`lib.nixosSystem` with `disko.nixosModules.disko` + `partitioning.nix`),
   not just parsed. Every partition, subvolume, and pinned UUID resolves as
   intended.

2. **`fileSystems.*` generation matches the live system exactly** -- for
   every mountpoint (`/`, `/home`, `/nix`, `/var/log`, `/.snapshots`,
   `/boot`), the `options` disko generates (including auto-added flags
   like `x-initrd.mount`, which disko infers the same way the live
   `hardware-configuration.nix` needed them) are byte-for-byte identical
   to what's live today.

3. **`boot.initrd.luks.devices.root` merge** -- disko (`initrdUnlock =
   true`) contributes `.device`; `../modules/boot/luks2/` separately
   contributes `.keyFile`/`.keyFileSize`. Evaluated the merge directly:
   no conflict, and every field except `.device` matches the live value
   exactly (see the one known divergence below).

4. **A full, real install-and-boot rehearsal in a sandboxed VM** -- not
   just evaluation. Formatted a virtual disk with disko using this exact
   config, installed a real NixOS system (disko + `partitioning.nix` +
   `modules/boot/luks2/` + `variables.nix`, mirroring what "wiring it in"
   would actually mean), rebooted, and confirmed:
   - the real `mount-usb-key.service` mechanism (not disko's own
     `settings.keyFile`) found and mounted a simulated "VirtualKeys" USB
     and unlocked LUKS via `/key/root.key`
   - `dmsetup info -c` showed the LUKS UUID exactly matching what's
     pinned in `partitioning.nix`
   - all five subvolumes (`@`, `@home`, `@nix`, `@log`, `@snapshots`)
     mounted at the correct paths
   - the ESP mounted correctly at `/boot`

   This caught two real bugs that pure evaluation never would have:
   pinning the LUKS `device` to the live by-uuid path breaks an actual
   format (chicken-and-egg -- that UUID only exists *after* formatting
   writes it), and disko can't safely target the VM's own live boot disk
   (mirrors why disko's own test harness reserves the first disk for the
   installer and never touches it).

## The one known, deliberate divergence

`boot.initrd.luks.devices."root".device` would become a
`/dev/disk/by-partuuid/<uuid>` path after a real disko-driven format,
not the by-uuid path `hardware-configuration.nix` currently has. Same
physical partition, different (equally stable) identifier -- see
`partitioning.nix`'s own comment on the `luks` partition for the full
reasoning. If this is ever wired in, `hardware-configuration.nix`'s
matching line would need updating to that new path (or, if disko is
wired in for real, it generates that line itself and the manual one
gets deleted entirely).

## Update: the full real config, built (not just evaluated)

Closed the "never built the full real config with disko in the mix" gap:
`disko.nixosModules.disko` + `partitioning.nix` are now in
`flake.nix`'s `nixosConfigurations.herauxvalle` modules, with
`disko.enableConfig = false` explicitly set. That flag is what keeps
this a build-verification exercise, not a live change -- with it false,
disko contributes nothing to `fileSystems`/`boot.initrd.luks.devices`/
`swapDevices`, so `hardware-configuration.nix` stays the sole live
source. Confirmed both ways:

- eval: `config.fileSystems.*` and `config.boot.initrd.luks.devices.root`
  are byte-identical to their pre-disko values
- build: `sudo nixos-rebuild dry-build` on the real, full
  `configuration.nix` (every module, not a stub) completed cleanly --
  only GRUB's config (from the `hidden = false` safety change, see
  below) and the toplevel needed rebuilding, no conflicts, no assertion
  failures

Also flipped `config.vars.boot.grub.hidden` to `false` (real countdown
menu instead of hidden/ESC-reveal) as a standing safety net for
whenever a real switch is attempted -- rollback to the previous
generation shouldn't depend on catching a timing window. Safe to revert
once this work is done.

Still not done: `disko.enableConfig` is still `false`. Flipping it to
`true` (or deleting `hardware-configuration.nix`'s blocks so disko's
generated values are the only ones left) is the actual live-behavior
step, and hasn't happened.

## What this does NOT prove

The rehearsal used a simulated USB and a synthetic test key over a
virtual disk -- it proves the *mechanism* (formatting, mounting, the
custom initrd unlock path) is sound, not that the real physical
hardware/USB/keyfile will behave identically. It also doesn't exercise
anything beyond `modules/boot/luks2/` + the filesystem layout -- the
rest of `configuration.nix`'s modules were not part of this rehearsal.

Wiring this in for real (deleting `hardware-configuration.nix`'s
`fileSystems`/LUKS blocks, adding `disko.nixosModules.disko` to
`flake.nix`'s `nixosConfigurations.herauxvalle` modules) is still a
separate, deliberate step -- not something to do as a side effect of
this verification.
