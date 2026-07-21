<!-- &desc: "Every real design fork hit while designing the live ISO -- override-list mechanism, why replacements.nix wasn't extended, the builtIn allowlist model, what was deliberately left alone, and why." -->

# Design decisions

## The override-list mechanism (`iso.nix`)

Rather than editing `Nixos/config/github/replacements.nix` (the
GitHub-publish text-redaction mechanism) or scattering individual
`lib.mkForce` lines through a new module, the ISO gets **one generic,
data-driven override list**: a flat attrset of dotted option paths ->
forced values, walked into real overrides by a small `lib.foldl'` +
`lib.setAttrByPath` + `lib.mkForce` helper. Explicitly requested this
shape mid-session ("a list that overwrites config vars no matter where
else, without path-specific bs") instead of hand-writing nested Nix
literals per option.

Works uniformly for two different kinds of paths:
- `config.vars.*` options (self-hosted service `enabled` flags, the
  Steam toggle, `usbRequired`/`sudoKeyfile` enables, the mountpoints
  master switch)
- raw NixOS options that have no `vars.*` indirection at all
  (`boot.loader.grub.enable`, `boot.supportedFilesystems.zfs`,
  `boot.loader.timeout`)

This is *not* the same problem `replacements.nix` solves -- see next
section.

## Why `replacements.nix` wasn't extended for this

Initial instinct (mine) was to extend `replacements.nix`'s
`replaceValues` list to also reset self-hosted services and Steam to
off for the *published* copy, on the theory that "opt-in features
should already be off by default for a stranger." Corrected mid-
session: `replacements.nix` already does exactly this for
`usbRequired.enable`/`sudoKeyfile.enable` (security posture -- a
stranger cloning this repo shouldn't also inherit this machine's exact
security posture turned on), but self-hosted services/Steam were never
covered by it, and that's a *separate* concern from security posture:
**size only matters for the live medium specifically**, not for anyone
building the full flake normally. A stranger who deliberately builds
`nixosConfigurations.herauxvalle` (not the `-iso` one) presumably wants
what's actually committed, self-hosted services included.

So: `replacements.nix` stays untouched for this work. All ISO-specific
trimming lives in `iso.nix`'s override list instead, which only ever
applies to the `-iso` flake output, never the published copy's normal
attribute.

One place this line blurred: `replacements.nix` genuinely does still
matter for the ISO, because `pacnix release` builds from the
*published* clone (see [usage.md](usage.md)) -- so the ISO
automatically inherits whatever security-posture resets
`replacements.nix` already does, for free, without `iso.nix` needing to
duplicate them. `iso.nix` still forces `usbRequired`/`sudoKeyfile` off
too, for clarity and so a *local* build of the `-iso` attribute (not
through the published-clone path) behaves the same way.

## `builtIn`: allowlist, not blocklist, for the general package list

Steam has its own dedicated `programs.steam.enable` toggle, so forcing
it off is a one-line override. The ~100-entry general package list
(`config.vars.packages.environment.packages.<source>.<name>`,
`Nixos/config/software/packages/packages.nix`) has no such per-entry
toggle -- every declared package normally just ships.

Rejected approach: manually block specific heavy packages (Swift, plus
whatever else turns out to be big) via the override list, same as
self-hosted services. Explicitly pushed back on mid-session: "I feel
like adding all of the packages is a meh thing... 90% of those
packages [aren't needed] on live env." The concern wasn't really about
size at that point -- it was that a blocklist requires remembering to
add every new heavy package, forever, and defaults to "included."

Landed on the opposite default instead: every package entry got a new
`builtIn` option (`Nixos/modules/packages/packages/default.nix`),
`type = bool`, `default = false`. `Nixos/modules/packages/packages/
main.nix`'s resolver skips any entry whose `builtIn` isn't `true` when
`config.vars.isoBuild` is `true` (a new cross-cutting flag, `Nixos/
modules/default.nix`, false everywhere except the ISO). On the real
machine `isoBuild` is `false`, so this is a complete no-op there --
confirmed via `nix eval`, and by comparing `environment.systemPackages`
counts before/after (308 real machine vs. 205 ISO, the ISO count being
base-installer/Hyprland packages only, zero opt-in personal packages
yet).

Naming: called `iso` originally, renamed to `builtIn` per explicit
request mid-session (kept `vars.isoBuild`, the *master switch* that
turns allowlist mode on at all, as its own separate and correctly-named
thing -- momentarily conflated the two, corrected immediately: "srry im
stupid... its what enables it").

Which packages actually get `builtIn = true;` is left entirely up to
whoever's building the ISO to decide later, per entry -- not guessed at
here. Documented with a worked example in `Nixos/glossar/software/
packages.nix` and `Nixos/modules/packages/packages/docs/README.txt`.

### The one thing `builtIn` couldn't solve: Swift

Swift (`~9.6 GiB` nominal, across 3 aliases) was going to need the same
treatment, but it structurally can't work as a simple override:
`config.vars.packages.environment.packages.pkgs` is an attrset a
downstream module can override a key's *value* in, not delete the key
from. Even forcing the `swift` entry to `{ }` still resolves to
installing the real, unversioned `pkgs.swift` (`resolve-default.nix`'s
own fallback for an empty entry) -- there's no "absent" value to force
it to. The `builtIn` option (declared on the *submodule itself*, so
every entry -- swift included -- carries it as a real field with a real
default) sidesteps this cleanly: `main.nix`'s resolver checks
`pkgCfg.builtIn` and skips resolving the entry *at all* when it's not
opted in, rather than trying to override what it resolves to. Swift
just becomes an entry that defaults to excluded, exactly like every
other package -- no special case needed once the mechanism was designed
around the resolution step instead of the value.

## SDDM / login: deliberately not special-cased

First draft planned to force `silentSDDM.enable = false` and stand up a
`getty` autologin straight into Hyprland for the live session, treating
it as a separate "live" login flow. Rejected mid-session ("why cant u
make the setup as rn work lol... no special cases"): SilentSDDM already
works on the real machine, and there's no established reason it
wouldn't work identically on the ISO. So `iso.nix` doesn't touch it at
all -- the ISO's login/session behaves exactly like the real machine's
until an actual observed problem says otherwise. Untested as of this
writing (see [verification-status.md](verification-status.md)) --
correctness here rests on "no reason it should differ," not on having
actually booted it.

## `pacnix release` / `pacnix install`: flat, not nested

Originally proposed as `pacnix setup release`/`pacnix setup install`
(a nested subcommand family, matching how `logs`/`plugins` have their
own internal sub-dispatch). Flattened to two plain top-level commands
per explicit request, for two reasons: it matches every other `pacnix`
command's style (`rebuild`, `validate`, `published`, ... all flat, no
grouping), and "setup" specifically collides in spirit with the
already-existing, unrelated `Installation/setup.sh` (`install.sh
--setup`, the post-reboot symlink/password step) -- keeping the names
flat and distinct avoids that confusion entirely.

## `pacnix install`: orchestrates existing scripts, adds no new destructive path

`Installation/format.sh` is already deliberately interactive (pick a
disk from `by-id`, retype the *resolved* path, type `WIPE` in caps) --
documented in `../../../Installation/doc.md` as a direct response to
"picking the wrong disk here is unrecoverable." Explicitly confirmed
this needed to be preserved as-is rather than streamlined: `pacnix
install` (run from the booted live ISO) just calls `format.sh`
unmodified, then `nixos-install`, then prints the same "reboot and run
`install.sh --setup`" instructions `format.sh` already prints today.
Every existing confirmation stays; this is one entry point over two
manual steps, not a new way to skip past them.
