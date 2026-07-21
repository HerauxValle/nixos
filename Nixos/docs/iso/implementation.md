<!-- &desc: "Every file touched or created for the live ISO, and exactly what each one does -- the concrete map to pair with design-decisions.md's reasoning." -->

# Implementation map

## New files

**`../../iso.nix`** -- the whole override mechanism (see
[design-decisions.md](design-decisions.md)): the dotted-path override
list, and `isoImage.contents` embedding the redacted flake clone at
`/dotfiles` (source read via `builtins.getEnv "ISO_DOTFILES_SOURCE"`,
coerced `/. + p` into a real path -- see
[bugs-and-fixes.md](bugs-and-fixes.md) for why the coercion is
required). Not imported by `configuration.nix` -- only by
`nixosConfigurations.herauxvalle-iso` in `../../../flake.nix`.

**`Scripts/Pacnix/cmd/release.sh`** -- `pacnix release`. Clones the
published GitHub repo fresh (same recipe as `published.sh`), resolves
the `-iso` attribute name via the shared `resolve_flake_attrs` helper,
builds `.config.system.build.isoImage` with `ISO_DOTFILES_SOURCE`
pointed at that very clone, copies the resulting `.iso` into the
directory `pacnix release` was invoked from (`$OLDPWD`, captured before
the script `cd`s into the clone).

**`Scripts/Pacnix/cmd/install.sh`** -- `pacnix install`. Meant to run
*inside the booted ISO* against the embedded `/dotfiles`. Calls
`/dotfiles/install.sh --format` unmodified, resolves the real
(non-`-iso`) attribute name the same way, then `nixos-install --root
/mnt --flake /dotfiles#<attr>`, then prints the existing "reboot, run
`install.sh --setup`" instructions.

**`Nixos/docs/iso/`** -- this directory.

## Modified files

**`../../../flake.nix`** -- new `nixosConfigurations.herauxvalle-iso`
output: nixpkgs's `installation-cd-minimal.nix` +
`inputs.home-manager.nixosModules.home-manager` +
`inputs.silent-sddm.nixosModules.default` (both needed explicitly --
the real config's modules list pulls these in too, and omitting them
here caused `The option 'home-manager' does not exist` at eval time,
see bugs doc) + `./Nixos/variables.nix` + `./Nixos/modules` +
`./Nixos/config` + `./Nixos/iso.nix`, deliberately *not*
`hardware-configuration.nix`/`partitioning.nix`.

**`Nixos/config/github/replacements.nix`** -- one new entry: renames
the new `nixosConfigurations.herauxvalle-iso` flake attribute to
`maxmustermann-iso` in the published copy, same pattern as the existing
`herauxvalle` -> `maxmustermann` entries (a new literal containing the
username needs its own redaction, same as any other). Also fixed an
unrelated regression this session's own edits caused -- see bugs doc
(`dotfilesBackup.enable`'s pinned `line = 44` needed updating to `37`
after the `grub.hidden` comment block was deleted from `config.nix`).

**`Nixos/modules/boot/luks2/luks2.nix`** -- gated the entire module
body behind `lib.mkIf (!config.vars.isoBuild)`. This file has no
`enable` option of its own (never needed one -- this machine always has
a LUKS root); the live ISO doesn't, and leaving it unconditional broke
a real build (see bugs doc). `iso.nix`'s override list no longer needs
to separately force off `boot.initrd.luks.devices`/`services.mount-
usb-key` now that the whole module is gated at the source.

**`Nixos/modules/packages/packages/default.nix`** -- new `builtIn`
option on the per-package submodule (bool, default `false`).

**`Nixos/modules/packages/packages/main.nix`** -- resolver skips any
package entry whose `builtIn` isn't `true` when `config.vars.isoBuild`
is `true`; otherwise unchanged.

**`Nixos/modules/default.nix`** -- new `vars.isoBuild` option (bool,
default `false`), declared alongside the existing `vars.alias` option
since both are small cross-cutting schema additions living outside any
one feature module.

**`Nixos/config/config.nix`** -- `grub.hidden` flipped back to `true`
(unrelated to the ISO work directly, requested alongside it -- the
`false` value was a temporary safety net from the disko-wiring
verification work, no longer needed).

**`Installation/format.sh`** -- resolves the target flake attribute
dynamically (`nix eval ... --apply builtins.attrNames`, filtering out
anything ending `-iso`) instead of the hardcoded literal
`nixosConfigurations.herauxvalle`. Needed because this script now also
runs against the *redacted* embedded `/dotfiles` copy (from `pacnix
install`), where that attribute has been renamed to a placeholder --
see bugs doc.

**`Scripts/Pacnix/cmd/published.sh`** -- refactored to use the new
shared `resolve_flake_attrs` helper instead of a bare `attrNames[0]`
(only ever correct with exactly one `nixosConfigurations` entry); added
a second dry-build for the `-iso` attribute's `config.system.build.
isoImage`, with `ISO_DOTFILES_SOURCE` exported for that check.

**`Scripts/Pacnix/lib/common.sh`** -- new `resolve_flake_attrs`
function: given a flake directory, prints the real (non-`-iso`)
attribute name then the `-iso` one (empty if none), erroring if more
than one non-`-iso` attribute exists. Shared by `published.sh` and
`release.sh` rather than duplicated.

**`Scripts/Pacnix/cmd/help.sh`** -- added `release`/`install` entries.

**`Nixos/glossar/software/packages.nix`** -- added a commented `builtIn`
example alongside the existing versions/aliasing examples.

**`Nixos/modules/packages/packages/docs/README.txt`** -- added a
"LIVE ISO (builtIn)" section documenting the option.
