<!-- &desc: "Every real build/eval failure hit while getting the live ISO to actually build, in order, with root cause and fix for each -- not hypothetical, every one confirmed live." -->

# Bugs found, in order (all confirmed live, not hypothetical)

Every one of these was hit by actually running a build, not predicted
in advance. Recorded chronologically since several later ones only
showed up after fixing an earlier one.

## 1. `home-manager` option doesn't exist

First `pacnix check` after adding the new flake output failed with
`The option 'home-manager' does not exist`. Root cause: the new
`nixosConfigurations.herauxvalle-iso` modules list included
`./Nixos/config` (which sets `home-manager.users.herauxvalle = ...`
indirectly) but not `inputs.home-manager.nixosModules.home-manager`
itself -- the module that actually *declares* that option. The real
config's own modules list includes it explicitly; copied the modules
list but missed this one. Fixed by adding both
`inputs.home-manager.nixosModules.home-manager` and
`inputs.silent-sddm.nixosModules.default` (needed for the same reason,
since `config/software/programs/silent-sddm.nix` sets options that
module declares).

## 2. `config`/`isoImage` at the same top level

`iso.nix`'s first draft returned `{ config = <overrides>; isoImage.contents
= [...]; }` -- two keys at the top level, one of them literally named
`config`. NixOS's module system takes the presence of a `config` key as
"this module uses the explicit config/options form," and then rejects
any *other* top-level key (`isoImage`) as unsupported. Fixed by merging
both into a single `config = lib.mkMerge [ (...) { isoImage.contents =
[...]; } ];`.

## 3. ZFS marked broken for this kernel

First real (non-dry-run) `nix build` of `config.system.build.isoImage`
failed: `Refusing to evaluate package 'zfs-kernel-2.4.3-7.1.3' ...
broken`. Root cause: nixpkgs's `installation-cd-minimal.nix` enables
ZFS support (`boot.supportedFilesystems.zfs`) by default for broad
hardware coverage, and this nixpkgs revision's ZFS build is marked
broken against kernel `7.1.3`. Not needed at all (real machine is
btrfs+LUKS). Fixed with one more override-list entry:
`"boot.supportedFilesystems.zfs" = false;`.

## 4. `boot.loader.timeout` conflict

Next build attempt failed at eval time: `The option
'boot.loader.timeout' has conflicting definition values` -- `5` from
`Nixos/modules/boot/grub/grub.nix` (this machine's real value), `10`
from the installer module. Both at equal (non-default) priority, so
neither won automatically. Since GRUB itself is already forced off for
the ISO (`boot.loader.grub.enable = false`), this option's actual value
barely matters -- fixed by forcing it to `10` (the installer's own
value) via the override list.

## 5. `initrd-bin-env` package conflict (util-linux)

Next build got much further (into a real derivation build) before
failing: `pkgs.buildEnv error: two given paths contain a conflicting
subpath: .../util-linux-minimal-.../bin/addpart and
.../util-linux-2.42.2-bin/bin/addpart`. Root cause:
`Nixos/modules/boot/luks2/luks2.nix` unconditionally adds
`boot.initrd.systemd.initrdBin = [ pkgs.util-linux ]` (the *full*
build, needed for its `-o ro` mount flag support) so the USB-keyfile
mount script can run; the installer base module separately adds its own
*minimal* util-linux build to the same initrd binary environment. Two
different derivations of "the same" package, both landing in one
`buildEnv`, is a hard conflict -- not something an override can paper
over (can't selectively "remove one contributed list item" from a
concatenated NixOS list option without already knowing the merged
result, which is circular).

Real fix, not a workaround: `luks2.nix` had no `enable` gate of its own
to begin with (this machine always has a LUKS root -- there was never a
prior reason for one). Gated the entire module body behind `lib.mkIf
(!config.vars.isoBuild)` instead of trying to override its individual
contributed options. This also made two of `iso.nix`'s override-list
entries redundant (`boot.initrd.luks.devices`, `boot.initrd.systemd.
services.mount-usb-key`) -- removed them once the whole module stopped
contributing anything on the ISO.

Introduced one syntax bug while writing this fix: added a stray extra
closing `)` after the `lib.mkIf (...) { ... }` block, on the theory
that the opening paren needed a separate matching close later. It
doesn't -- `lib.mkIf cond attrset` is just two function arguments in
sequence, and the `(!config.vars.isoBuild)` parens already close
themselves on the same line. The extra `)` caused `syntax error,
unexpected ')'` on *both* configurations (this file is shared), caught
immediately by `pacnix check`.

## 6. `isoImage.contents`'s `source` needs a real path, not a string

First fully "successful" (no errors) local build actually failed at the
very last step: `xorriso ... FAILURE : Cannot determine attributes of
source file '/home/herauxvalle/Dotfiles' : No such file or directory`.
Root cause: `builtins.getEnv "ISO_DOTFILES_SOURCE"` returns a plain Nix
*string*, not a path value -- and only real path values trigger Nix's
"copy this into the store as a build input" mechanism during
evaluation. A bare string just gets passed through literally, so the
sandboxed builder (which can't see the host filesystem at all) had
nothing to read. Fixed with the standard string-to-path coercion,
`/. + p`, which forces the copy-to-store to actually happen before the
build starts.

## 7. Stale pinned `line` number after an unrelated edit

Flipping `Nixos/config/config.nix`'s `grub.hidden` back to `true`
deleted a 6-line comment block along with the value change, shifting
every line number below it. `Nixos/config/github/replacements.nix` has
one entry pinned to `line = 44` specifically to redact
`dotfilesBackup.enable = true` (a bare `enable = true;` search would
also match `usbRequired`/`sudoKeyfile`'s lines, hence the line pin).
The next `pacnix rebuild` printed a real warning (`replaceValues find
text 'enable = true;' does not currently appear on line 44 ... stale
entry?`) that would otherwise have been easy to miss -- the redaction
silently stopped applying, meaning the *first* push after this session's
grub-hidden edit had `dotfilesBackup.enable = true` (not the intended
`false`) in the published copy. Caught by actually reading the rebuild
output rather than assuming success from exit code 0, and fixed by
updating the pin to the new correct line (`37`), followed by another
`pacnix rebuild` to push the correction.

## 8. `pacnix`'s own scripts don't hot-reload

`pacnix published` still failed with the *old*, already-fixed
"`ISO_DOTFILES_SOURCE` is unset" error even after editing
`published.sh` to export it. Root cause: `pacnix` is itself a Nix
package built from a snapshot of `Scripts/Pacnix/` (confirmed by
diffing the running `/nix/store/*-pacnix/opt/src/cmd/published.sh`
against the live source file -- they differed) -- editing the source
tree doesn't change what the already-built `pacnix` binary on `PATH`
runs until another `pacnix rebuild` picks up the new snapshot. Same
category of thing already known for Casket (`cas` needing a rebuild to
pick up source changes) -- applies to `pacnix` itself too, not just
things it manages. Fixed by rebuilding again before retesting.

## General pattern across all of these

Every one of these was caught by actually attempting a real build (or
reading a rebuild's full output, not just its exit code), never by
reasoning about it in advance. Consistent with this repo's existing
disko-work discipline (`../disko-wiring-verification.md`,
`../../../Installation/doc.md`) -- eval-level checks (`pacnix check`)
are fast and worth running first, but they don't substitute for an
actual build when the failure mode is "two derivations conflict at
build time" or "a builder can't see a host path."
