# `lib/mk-from-native/` -- wrapping something nixpkgs already provides

Sibling to `lib/service/` (`mkSelfHostedService`/`mkActionService` -- build
a self-hosted service completely from scratch) and `lib/venv/` (the
Python FHS+pip lifecycle). This directory is for the opposite case: a
service where nixpkgs (or NUR) already ships a genuinely mature module or
package, and reimplementing it from scratch would just be worse,
duplicated maintenance. The goal here is always the same thin shape:
apply this framework's own conventions (`enabled`, `host`/`port`,
`requireMounts`, `environmentFile`, ...) on top of the real thing,
never rebuild what's already correct.

Five real categories, matched to how nixpkgs/NUR actually split things
(`services.<name>` vs `programs.<name>` vs a plain `pkgs.<name>`
package, each with a genuinely different option tree or none at all).
Each category gets its own flat file directly under this directory
(`services.nix`, `programs-root.nix`, ...), same one-file-per-concern
shape `lib/service/` and `lib/venv/` already use -- not a subdirectory
per category, there's no second file any of these would need yet:

- **`services.nix`** -- wrap a `services.<name>` NixOS module (a real
  systemd-backed service, like Immich's `services.immich`). **The only
  implemented category** -- `mkFromNativeService`. Immich is the first
  and only real caller.
- **`programs-root.nix`** (not yet written) -- wrap a system-level
  `programs.<name>` NixOS module (installs + configures something
  machine-wide, no systemd service of its own). No current caller.
- **`programs-user.nix`** (not yet written) -- wrap a home-manager
  `programs.<name>` module. Deliberately a separate category from
  `programs-root`, not folded into it -- home-manager's option tree is
  genuinely different from a system-level NixOS module (different
  `config.` namespace, different activation model), so a shared helper
  would have to branch on which kind of `programs.*` it's even looking
  at. No current caller.
- **`pkgs.nix`** (not yet written) -- wrap a plain `pkgs.<name>` package
  with no service/config layer at all (install it, expose a binary,
  nothing more -- no systemd unit, no options tree beyond what the
  framework itself adds). No current caller.
- **`nur.nix`** (not yet written) -- same shape as `pkgs.nix`, but
  sourced from the Nix User Repository instead of nixpkgs proper (a
  separate category because NUR packages aren't guaranteed the same
  review/maintenance bar nixpkgs proper has -- worth knowing which one a
  given service actually came from). No current caller.

Per this framework's own "don't generalize until a second real need
exists" rule (`docs/conventions.md`): only `services.nix` has real code.
The other four are intentionally documented here, not stubbed with empty
placeholder files -- that would just be unused dead code sitting in the
tree with no caller to validate it against. When a real service needs
one of them, write it the same way `services.nix` was written: read the
real thing being wrapped first (not guessed), keep the helper itself
scoped to what's genuinely common across *any* case in that category,
and leave everything service-specific in that service's own `<name>.nix`
`extraConfig`.

See `../../immich/` for the one real example of how a caller uses
`mk-from-native/services.nix` end to end, and this framework's
`docs/architecture.md` / `docs/adding-a-service.md` for the shared
conventions every service (wrapped or from-scratch) follows regardless
of which category it's built from.
