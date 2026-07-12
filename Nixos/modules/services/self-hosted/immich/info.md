# Immich -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./immich.nix`. Implementation detail
pieces: `./lib/update.nix`. Real values: `Nixos/config/self-hosted/immich.nix`.
Shared helper: `../lib/mk-from-native/services.nix` (`mkFromNativeService`,
re-exported from `../self-hosted.nix`).

Unlike every other service in this tree, Immich **wraps nixpkgs' own
mature `services.immich` module** instead of being built from scratch
with `mkSelfHostedService` -- see "Why wrap instead of build" below.
Consequence: no `package.nix`, no `dataDir`/`storage`/`teardownPaths`,
no pinned `version`/`hash` anywhere in this directory.

## Why wrap instead of build

Every other service exists in this framework specifically because
nothing mature already existed for it in nixpkgs. Immich is the opposite
case: `nixos/modules/services/web-apps/immich.nix` (466 lines, read in
full before writing anything here) already correctly handles Postgres
with `pgvector`+`vectorchord` (auto-created, auto-`CREATE EXTENSION`'d,
auto-reindexed on extension upgrade), Redis (`services.redis.servers.
immich`, unix-socket by default), the ML sidecar (its own systemd unit
with a real `CacheDirectory`), full systemd hardening on every unit, and
a real secrets mechanism. Rebuilding any of that from scratch would be
strictly worse, duplicated maintenance -- so this port applies the
framework's own thin conventions (`enabled`, `autoStart`, `host`/`port`,
`requireMounts`, `environmentFile`) on top of the real thing instead,
via `mkFromNativeService` (`../lib/mk-from-native/services.nix`, the
first and only implemented category of that shared, general "wrap
something nixpkgs already provides maturely" helper -- see its own
`README.md` for the other four, unimplemented categories).

The package itself tracks nixpkgs' own `pkgs.immich` (`2.7.5` as of
writing), not a separately pinned `version`/`hash` -- nixpkgs does the
real maintenance work (dependency tree, build, security patches) for
something this architecturally complex. No `update`/`update:apply`
actions write anything as a result -- see "systemd units" below.

## Options (`vars.selfHosted.immich`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = `services.immich.enable` (+ `.database.enable`/`.redis.enable`, set explicitly even though not strictly required) wired on. `false` = none of it exists. No teardown mechanism -- see "Install/uninstall" below. |
| `autoStart` | bool | `true` | `false` = exists, `systemctl start immich-server`-able, not on boot/rebuild. The wrapped module hardcodes `wantedBy = [ "multi-user.target" ]` with no toggle of its own -- `immich.nix` force-overrides it (`lib.mkForce`) so this actually has an effect. Currently `false` in this machine's real config, matching every other service. |
| `mediaLocation` | str | *required* | Passed straight to `services.immich.mediaLocation`. No generic default -- real value is `~/Images/Media/Cloud`, see "Real data placement" below. |
| `host` | nullOr str | `null` | Optional override for `services.immich.host` -- a real, already-typed option on the wrapped module, no construction trick needed (unlike Ollama) and no API-push mechanism needed (unlike Jellyfin). `null` = its own default (`"localhost"`) applies untouched. |
| `port` | nullOr port | `null` | Same shape, `services.immich.port`, default `2283`. |
| `requireMounts` | listOf str | `[ ]` | Checked as a mountpoint before `immich-server` (only that unit -- `immich-machine-learning` never touches `mediaLocation`) starts, via `mkFromNativeService`'s `mountCheckUnits`. Real value: the "Media" vault's own mountpoint. |
| `environmentFile` | nullOr str | `null` | Passed to `services.immich.secretsFile`. **CAUTION**: unlike this framework's own `environmentFile` convention everywhere else (`EnvironmentFile = "-${path}"`, missing file = non-fatal), the wrapped module's own `EnvironmentFile = mkIf (cfg.secretsFile != null) cfg.secretsFile` has **no** `-` prefix -- pointing this at a file that doesn't exist yet is a hard unit-start failure. Only set once the real file already exists. |
| `enableMachineLearning` | bool | `true` | Pass-through to `services.immich.machine-learning.enable`. |
| `environment` | attrsOf str | `{ }` | Pass-through to `services.immich.environment`. |
| `machineLearningEnvironment` | attrsOf str | `{ }` | Pass-through to `services.immich.machine-learning.environment`. |

## Real data placement -- a vault other services don't use

The old bash framework's real config
(`~/Scripts/Self-hosted/Immich/configuration/variables/launch.sh`)
targeted `IMMICH_STORAGE=("upload|$HOME/Images/Media/Cloud")`, inside a
**`Media` Casket vault (250GB)** -- a completely separate vault from
`SelfHosted`, the one every other migrated service uses. Missed on the
first pass of this port (checked `SelfHosted` and the external `Storage`
drive, not this one) -- found only because the user pointed at it
directly after the first draft claimed "never ran with real data,"
which was wrong. Once mounted (`cas Media open`), `~/Images/Media/Cloud/`
turned out to hold **43GB of real, genuine Immich internal structure**:
`upload/`, `library/`, `thumbs/`, `profile/`, `encoded-video/`,
`backups/`, each with its own `.immich` marker file and real per-user
UUID-sharded content (confirmed by directly inspecting the directory
tree, not assumed from the old script alone).

**What this data actually is, and isn't**: the raw files are real and
worth keeping in place -- `mediaLocation` points straight at this path,
nothing copied or migrated. But the actual Postgres database (accounts,
albums, face-recognition index -- everything that makes Immich *know*
these files are assets) was **never vault-backed** the same way (the old
framework's own `database.sh` is explicit: Postgres/Redis are plain
system services living in the OS's standard locations, out of scope for
that folder's `storage.sh` entirely) and `Cloud/backups/` -- Immich's own
internal DB-dump feature's target folder -- is empty except for its
`.immich` marker, meaning that feature was never actually completed/used
either. So the real Postgres database is gone; this is a fresh database
on first start, pointed at real but currently-*orphaned* files (still
sharded under the old, now-nonexistent user's UUID directory tree).
**The photos won't "just appear"** the moment the service starts -- a
new admin account has to be created through the normal setup flow, and
the old files will need to be reconciled by hand (re-upload, or Immich's
own external-library feature pointed at the same path) rather than being
auto-recognized. Worth doing regardless of that friction: the bytes are
real and there's no reason to duplicate 43GB elsewhere or discard them.

**Ownership**: every directory under `Cloud/` is `root:root` (inherited
from however the old install actually ran). The wrapped module's own
`systemd.tmpfiles.settings.immich."${mediaLocation}".e` rule only
*adjusts* `mediaLocation`'s own ownership (type `e`, non-recursive) --
its own doc comment says as much: "the directory has to be created
manually such that the immich user is able to read and write to it."
`immich.nix` adds a real, recursive `Z` tmpfiles rule
(`Z ${mediaLocation} 0700 <user> <group> - -`) to actually fix ownership
on the whole tree, every activation, idempotent.

## Install/uninstall of the package itself -- ordinary Nix generations, nothing built

`enabled` still means what it means everywhere else: `true` wires
`services.immich.enable` (+ `.database.enable`/`.redis.enable`) on,
`false` flips them back off so the next rebuild's generation has none of
it. The genuine difference from every other service: there's no
framework-level `dataDir` here for `mkTeardownActivationScript` to sweep
on `enabled = false` -- but the installed *package* doesn't need one to
actually go away. The moment `enabled = false` is rebuilt, the new
generation's closure no longer references `pkgs.immich` (or the
Postgres/Redis derivations configured for it) at all; the previous
generation holds a GC root until it's no longer current, at which point
ordinary `nix-collect-garbage` reclaims it -- exactly like every other
service's *package* layer already works (only their *data directories*
need `teardownPaths`, because `/nix/store` isn't where user data lives).
Real user data (`mediaLocation`, the Postgres database content) is never
auto-deleted, matching `docs/conventions.md`'s "Destructive vs.
recoverable" -- there's simply nothing here that needs a scripted
teardown path the way ComfyUI's `output/`/`temp/` do.

## No custom Postgres/Redis tuning, no separate module elsewhere

`services.postgresql`/`services.redis.servers.immich` are configured
entirely inside `immich.nix`'s own `extraConfig` -- confirmed nothing
else in this repo declares either, so per `docs/conventions.md`'s "don't
generalize until a second real need exists," they stay scoped here, not
extracted into a shared `postgresql.nix`/`redis.nix` module. If Immich
itself ever needs real tuning (connection pool size, Redis `maxmemory`),
that stays inside Immich's own config too, not a generic knob.

## `settings` -- Immich's own config surface, left `null`

`services.immich.settings` (freeform JSON, backed by `IMMICH_CONFIG_FILE`)
is Immich's own file-based config surface, separate from env vars -- not
to be confused with SearXNG's unrelated `settings.yml` from earlier this
migration, just the same generic option name reused by a different
upstream project. Left `null`, matching the wrapped module's own default
-- its own docs explicitly support configuring the rest through the web
UI instead, and nothing about this first port needs it set.

## Autostart -- one real override on top of the wrapped module

`services.immich` hardcodes `wantedBy = [ "multi-user.target" ]` on both
`immich-server` and `immich-machine-learning`, with no toggle of its own
-- unlike literally every other service here, which gets `autoStart` for
free from `mkSelfHostedService`. `immich.nix` adds it back via
`lib.mkForce` on both units' `wantedBy` (the ML unit's override gated on
`cfg.enableMachineLearning`, so it never springs the unit into existence
when ML is disabled) so this one service doesn't drift from the rest of
the framework's real, current, machine-wide stance (every service is
currently `autoStart = false` -- installed, not on-boot yet). Standard
NixOS practice (any module can override another module's option via a
priority function), not a hack.

## systemd units

- `immich-server` / `immich-machine-learning` (if `enableMachineLearning`)
  / `postgresql` / `redis-immich` -- all built entirely by the wrapped
  `services.immich` module, not by this framework's own
  `mkSelfHostedService`. `immich-server`'s `preStart` gets the
  `requireMounts` check appended (via `mkFromNativeService`'s
  `mountCheckUnits`) -- NixOS's own `preStart` option is a mergeable
  `types.lines`, so this concatenates cleanly onto whatever the wrapped
  module's own `preStart` already contributes (nothing, currently --
  that's only non-empty when `settings != null`), never replaces it.
- `self-hosted-immich@update` / `@update:apply` -- fully independent of
  the units above (`mkActionService`'s own template, same mechanism
  every service uses, never `wantedBy`, never a dependency of anything).
  Both print-only, always -- there's no `config/self-hosted/immich.nix`
  version/hash field to write, since the package tracks nixpkgs. `update`
  reports the nixpkgs-tracked version (`pkgs.immich.version`, baked in
  at eval time) against upstream's latest GitHub release; `update:apply`
  runs the identical check but prints the real instructions for actually
  getting a newer one (bump this flake's `nixpkgs` input) instead of
  writing anything.

## Workflows

**Check for a newer version**: `systemctl start self-hosted-immich@update`
-- prints current (nixpkgs-tracked) vs latest upstream, network call to
GitHub's API. `@update:apply` prints the same comparison plus the real
steps to bump nixpkgs -- neither ever touches a file.

**Create an admin account / reconcile the old photos**: complete
Immich's normal first-run setup (fresh Postgres database, see "Real data
placement" above), then either re-upload from a client, or use Immich's
own external-library feature pointed at `mediaLocation` to bring the
existing files back into the catalog -- there is no automated
reconciliation here, the old files are orphaned relative to a brand-new
database.

**Full teardown**: set `enabled = false`, rebuild -- `services.immich.
enable`/`.database.enable`/`.redis.enable` all go off, no units exist.
`mediaLocation` and the Postgres database content are never touched by
this (no teardown mechanism reaches them at all -- see "Install/uninstall
of the package itself" above). Flip back to `true` and rebuild to
reinstall; nothing about the previous data changes either way.
