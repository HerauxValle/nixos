# Jellyfin -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./jellyfin.nix`. Implementation detail
pieces: `./lib/{package,update,rescan,plugins-sync,theme-sync,network-sync,wait-for-api}.nix`.
Real values: `Nixos/config/self-hosted/jellyfin.nix`.
Real theme source: `Dotfiles/Themes/Jellyfin/ElegantFin/theme.css` --
same top-level convention as every other themed app in this repo, not
under `Nixos/config/`.

Binary comes from a pure Nix fetch (`lib/package.nix`), same shape as
Ollama/Stash -- no venv, no FHS sandbox. A self-contained .NET publish,
patched with `autoPatchelfHook` for its native library dependencies (see
"Two real library bugs" below for the two that weren't caught by that
alone). Real, working machinery beyond the live service itself: theme
CSS embedded directly into Jellyfin's own branding config, and a
declarative (currently-empty) plugin-repo/plugin-install mechanism --
both need Jellyfin's own REST API, so both run in `postStart`, not
`preStart`.

## Options (`vars.selfHosted.jellyfin`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service and actions all exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" below). |
| `dataDir` | str | `~/Applications/Networking/Jellyfin` | Plain base dir -- real writable subdirs `cache`/`transcode`/`log` live directly here; `config`/`data`/`libraries/<name>` are all storage-backed symlinks (see `storage`). |
| `autoStart` | bool | `true` | Same meaning as every other service here. Currently `false` in this machine's real config. |
| `version` | str | *required* | Jellyfin release version to pin. |
| `hash` | str | *required* | SRI sha256 of that version's linux amd64 release tarball. |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process -- `DOTNET_GCConserveMemory`/`DOTNET_EnableDiagnostics` are real, confirmed-used (ported from the old `launch.sh`). `JELLYFIN_LOG_LEVEL` was declared there too but confirmed dead. |
| `port` | nullOr port | `null` | Optional override, pushed to Jellyfin's own network config (`InternalHttpPort`+`PublicHttpPort`) via its REST API in `postStart` (`lib/network-sync.nix`) -- the only real mechanism, confirmed by testing directly: `ASPNETCORE_URLS` is explicitly ignored. `null` = `network.xml`'s own port applies untouched. **No `host` option exists** -- Jellyfin's network config has no bind-address field at all (Kestrel always listens `0.0.0.0`, confirmed from both a real `network.xml` and Jellyfin's own startup log). See "Theme: embedded CustomCss" below's sibling section, "`port`: API push, not env/CLI", for the full mechanism and its one real limitation (can't apply until an admin key exists). |
| `storage` | listOf `{src,dest}` | `[ ]` | Two different kinds of real data behind the same mechanism -- see "Real, migrated data" below for the full list and why it's shaped this way. |
| `requireMounts` | listOf str | `[ ]` | Paths checked as mountpoints before `preStart` runs. Real config needs both the Casket vault and the external Storage drive. |
| `teardownPaths` | listOf str | `[ ]` | Non-empty on purpose (ComfyUI's shape) -- `["cache" "transcode" "log"]`. See default.nix's own comment: nested storage entries (`libraries/<name>`) aren't correctly recognized by the default "everything but storage" rule, which only matches top-level basenames. |
| `fdLimit` | nullOr int | `65536` | `LimitNOFILE` on the live unit -- real, ported from the old `runtime.sh`'s `ulimit -n`. Required adding a new `limitNoFile` param to `mkSelfHostedService` itself (opt-in, `null` by default, no effect on any other service). |
| `ffmpeg` | nullOr package | `null` | Package providing `bin/ffmpeg`, passed to Jellyfin's real `--ffmpeg` flag. `null` = `pkgs.jellyfin-ffmpeg` (resolved in `jellyfin.nix`, not here). Deliberately not "system ffmpeg on PATH" (the old `deps.sh`'s approach). |
| `theme.enable` | bool | `true` | Master switch for the theme sync. |
| `theme.cssPath` | nullOr path | `null` | Path to the real `theme.css` file. Its content is embedded directly into Jellyfin's branding `CustomCss` (marker-delimited, so any other manual CSS added via the dashboard survives). |
| `pluginRepos` | listOf `{name,url}` | `[ ]` | Written into Jellyfin's own `repositories.xml` every start, but only if non-empty -- an unconditional write with an empty list risks overwriting Jellyfin's own built-in default repo with nothing, unconfirmed whether that's actually safe. |
| `plugins` | listOf `{guid,version}` | `[ ]` | Installed via Jellyfin's own REST API in `postStart`. Nothing removes an undeclared-but-installed plugin automatically (unlike ComfyUI's nodes/models) -- Jellyfin's plugin uninstall isn't a simple file deletion, not safe to automate blind. |

## Two real library bugs, both found on real runs, not guessed

The prebuilt tarball's `autoPatchelfHook` pass resolves every *static* ELF
dependency correctly (confirmed: the build itself fails loudly if
anything's actually missing) -- but two of .NET's native interop shims
`dlopen()` their target library by plain SONAME at runtime instead,
which `autoPatchelfHook`'s RPATH-based fixup never touches:

- `libSystem.Globalization.Native.so` -> `libicuuc.so`/`libicui18n.so`
  (crash: "Couldn't find a valid ICU package").
- `libSystem.Security.Cryptography.Native.OpenSsl.so` ->
  `libssl.so`/`libcrypto.so` (crash: "No usable version of libssl was
  found"). This one only ever surfaced running under a genuinely
  *minimal* environment (a real systemd unit) -- an interactive shell has
  enough ambient library paths to accidentally paper over it, which is
  exactly what happened here the first time around.

Fixed in `lib/package.nix` via `makeWrapper --prefix LD_LIBRARY_PATH :
"${icu}/lib:${openssl.out}/lib"` on `$out/bin/jellyfin` (a real wrapper
script now, not a thin symlink to the payload -- has to be, to set this).
`dontStrip = true` is also required (nixpkgs' own `buildDotnetModule`
defaults this too) -- the default strip phase corrupts .NET's managed
assemblies (PE format, not ELF), confirmed by a checksum diff against the
untouched tarball and a real "incorrect format" startup failure without
it. `liblttng-ust.so.0` (wanted by the tracing/diagnostics provider) is
deliberately ignored, not satisfied -- the live process runs with
`DOTNET_EnableDiagnostics=0`, so that code path is never exercised.

## `IsStartupWizardCompleted` -- a real app-level bug, not Nix's

Jellyfin hard-crashes (`SqliteException: no such table:
__EFMigrationsHistory`) if `config/system.xml`'s
`<IsStartupWizardCompleted>` says `true` while the actual database
doesn't exist yet -- it skips the first-run bootstrap path entirely and
goes straight to a migration step that assumes a table an actual fresh
install would already have. Hit this for real: the recovered
`system.xml` (see "Real, migrated data" below) was from an
already-fully-set-up install, but no `data/jellyfin.db` was ever backed
up, so pairing them together hit exactly this. Confirmed by isolating
it -- removing *just* this one flag's value (`true` -> `false`,
`config/system.xml` in the vault, a one-line change, same class of fix
as SearXNG's `secret_key` placeholder) let Jellyfin bootstrap a real,
working database cleanly; nothing else in the recovered config needed
touching.

## The real database path has an extra `data/` level

`--datadir X` does **not** mean `X/jellyfin.db` -- Jellyfin creates its
*own* `data/` subdirectory inside whatever `--datadir` you give it, so
the real file is at `X/data/jellyfin.db` (confirmed both by a real run
and by the old `rescan.sh`'s own `DB="$JELLYFIN_DATA_DIR/data/jellyfin.db"`).
Since this module's own `cfg.storage` already has a `data` entry
(`dataDir/data` -> the vault), the *actual* live database ends up at
`dataDir/data/data/jellyfin.db` -- two `data` levels, not one. Every
script here that needs the real db path (`wait-for-api.nix`,
`rescan.nix`) accounts for this.

## Nested storage entries needed a real framework fix

`libraries/media-movies` (a storage `src` with a `/` in it) exposed a gap
in `mk-self-hosted-service.nix`'s existing ancestor-ownership-fixup logic
-- it only handled the `homeDirectory` -> `dataDir` chain, not
`dataDir` -> a nested storage `src`. `systemd-tmpfiles` auto-creates the
missing intermediate directory (`dataDir/libraries`) as `root:root` as a
side effect of the `L+` line itself, which trips the same "unsafe path
transition" safety check the existing ancestor-fixup code was written
for -- confirmed on a real run: the symlinks under `libraries/` silently
never got created, the directory just sat there empty and root-owned.
Fixed generically in `mk-self-hosted-service.nix` (a new
`storageSrcAncestorDirs` computation, same `d`+`z` treatment as the
existing `ancestorDirs`) -- this is the first service with a nested
storage `src`, but the fix applies to any future one too.

## Theme: embedded CustomCss, not a separate server (revised design)

The first version of this used a separate sidecar systemd unit (a tiny
CORS-enabled static file server, ported near-verbatim from the old
`theme-server.sh`) serving `theme.css`, with an `@import url(...)` line
pushed into Jellyfin's branding config pointing at it -- faithful to the
old bash framework's actual mechanism, and it worked. Reverted once it
turned out to depend on a hostname (`jellyfin.local`, resolved via mDNS)
that isn't real infrastructure on this machine yet -- confirmed the
setup wizard/theme wouldn't reliably resolve from other devices without
it. (Also hit a real systemd lesson along the way: `PartOf=` on the
sidecar unit only propagates *stop*/*restart*, not *start* --
`Wants=`/`After=` on the *main* service, pointing at the sidecar, is
what's actually needed to make starting jellyfin also start a
dependent unit. Moot now that the sidecar's gone, but worth remembering
for any future multi-unit service.)

Current design: `lib/theme-sync.nix` reads `theme.cssPath`'s real content
directly (no serving, no hostname, no port) and embeds it into
Jellyfin's branding `CustomCss` field, marker-delimited (`/* BEGIN
nix-managed theme ... */` / `/* END ... */`) so it only ever replaces its
own block, never anything added manually via the dashboard outside it.
Since `CustomCss` is served as part of Jellyfin's own response to every
client, this works from any device that can already reach Jellyfin at
all -- LAN, VPN, remote, no DNS/mDNS dependency whatsoever. Trade-off:
editing `theme.css` needs a re-sync (restart, or a future manual action)
to take effect, instead of a live `@import` re-fetch -- themes don't
change often enough for that to matter in practice.

## `port`: API push, not env var or CLI flag

Three services in this repo now have `host`/`port`-style options
(Ollama, SearXNG, Jellyfin), and all three use a genuinely different
mechanism, worth being explicit about:

- **Ollama**: `OLLAMA_HOST` is a real env var Ollama reads directly.
  `host`/`port` here just construct that string and win over
  `environment.OLLAMA_HOST` if set.
- **SearXNG**: `SEARXNG_BIND_ADDRESS`/`SEARXNG_PORT` are real, native env
  var overrides SearXNG's own `settings_defaults.py` declares --
  cleanest of the three, no file-touching or API call needed at all.
- **Jellyfin**: neither exists. Confirmed directly (`ASPNETCORE_URLS`
  explicitly ignored on a real run -- "Overriding address(es) ...
  Binding to endpoints defined via IConfiguration ... instead") and by
  inspection (no CLI flag for it either). The *only* real way to change
  it is Jellyfin's own REST API (`/System/Configuration/network`) -- the
  same one its dashboard's own Networking page uses under the hood.
  `lib/network-sync.nix` pushes `cfg.port` there in `postStart`, same
  wait-for-api + admin-key pattern as the theme sync and plugin install.

**The real asymmetry this creates**: Ollama/SearXNG's overrides apply
from the very first start, no matter what. Jellyfin's `port` can only
apply *after* the live API is up **and** an admin key exists -- which,
on a genuinely fresh install (no setup wizard completed yet), it won't.
So setting `port` on a brand-new Jellyfin install silently does nothing
until you've completed the wizard once. Not a bug, just a real
consequence of Jellyfin not exposing any pre-startup override for this
the way the other two do.

**Also real**: pushing a new port via the API updates `network.xml`
(the *stored* config) but does **not** rebind Kestrel's already-listening
socket -- Jellyfin needs an actual restart after the push for the new
port to take effect, same as any config change that only applies at
startup.

## Two things confirmed dead, not ported as working options

Grepped the entire old bash tree for both -- neither ever reached a real
CLI flag or API call anywhere:

- **Hardware acceleration** (`configuration/variables/hwaccel.sh`'s
  `JELLYFIN_HW_ACCEL`/`JELLYFIN_VAAPI_DEVICE`/etc). Jellyfin's real
  transcode config is entirely self-managed via its own
  `encoding.xml`/dashboard, never touched by any script.
- **Bind address/ports** (`network.sh`'s `JELLYFIN_BIND_ADDRESS`/
  `JELLYFIN_HTTP_PORT`/`JELLYFIN_HTTPS_PORT`/`JELLYFIN_DLNA_ENABLED`/
  `JELLYFIN_AUTODISCOVERY_ENABLED`) -- confirmed from a recovered real
  `network.xml` that Jellyfin actually used its own default (8096), never
  the "6050" declared in that file. `plugins.sh` did reference
  `JELLYFIN_HTTP_PORT` for its own API base URL, a real latent bug in the
  *old* framework (assumed the wrong port) -- not repeated here;
  `wait-for-api.nix`/`rescan.nix` both read the real port straight out of
  `network.xml`'s `<InternalHttpPort>` instead, same mechanism the old
  `theme-sync.sh`/`rescan.sh` already used correctly.

Metadata-provider keys (`library.sh`'s `TMDB_API_KEY`/`TVDB_API_KEY`/
`ANIDB_USER`/`ANIDB_PASS`) were *also* confirmed dead the same way, but
unlike the two above, `environmentFile` support is wired anyway (see
next section) -- real plugins may genuinely want these as env vars, just
unconfirmed which ones/how without actually installing one.

## Secrets (`secrets self-hosted jellyfin`)

`environmentFile` is wired on both the live service and the action
service, pointing at `/etc/nixos-secrets/self-hosted/jellyfin/tokens.env`
(root:root 600, written by `Scripts/Secrets/cmd/self-hosted.sh` -- a
real, already-generic, already-working command, confirmed by reading it
directly). Two real uses:

- Metadata-provider API keys, if you find a real plugin that reads one
  as an env var (unconfirmed which ones do -- see above).
- `JELLYFIN_API_KEY` -- a manually-created Jellyfin API key (Dashboard ->
  API Keys -> +). `lib/wait-for-api.nix`'s `api_key()` prefers this over
  the dynamic sqlite lookup (grab the most recently created session
  token) when set -- stable/explicit once you set it up, but zero-setup
  by default: the theme sync and plugin install both work out of the box
  before you ever create one, same as the old `theme-sync.sh`/
  `rescan.sh` did.

## systemd units

- `self-hosted-jellyfin.service` -- the live process. `preStart`: (1)
  `mkdir -p` the plain scratch dirs (`cache`/`transcode`/`log`), (2) write
  `config/repositories.xml` from `cfg.pluginRepos` (only if non-empty).
  `postStart`: theme branding sync (only if `theme.enable` and
  `theme.cssPath` set), then plugin installs (only if `cfg.plugins != [ ]`),
  then network config push (only if `cfg.port != null`) -- all three
  bounded-poll-until-ready first (`lib/wait-for-api.nix`), all three
  gracefully skip (exit 0, don't fail the service) if no admin API key
  exists yet. `LimitNOFILE=65536`, `TimeoutStartSec=infinity`, same as
  every service here.
- `self-hosted-jellyfin@update` / `@update:apply` -- checks
  `repo.jellyfin.org`'s latest-stable listing against `version`.
  Print-only / writes `version`+`hash` into
  `config/self-hosted/jellyfin.nix` directly.
- `self-hosted-jellyfin@rescan` -- ported from the old `rescan.sh`, a
  real (if surgical) DB-repair tool for stale library-ancestor rows after
  a library path changes. Not automatic -- a deliberate, by-hand
  maintenance action. Stops the service, edits the db directly via sqlite,
  restarts, triggers a scan via the API once back up.

## Real, migrated data

- **`config/`** -- recovered from a backup-drive snapshot of the old
  bash framework's `Applications/Networking/Jellyfin/config/` (never
  vault-backed there either), including a real user profile
  (`users/HerauxValle/`), the theme `@import` already set in
  `branding.xml` (confirming the old theme mechanism genuinely worked),
  and `network.xml` showing the real port was always 8096. One value
  fixed on the way in: `system.xml`'s `IsStartupWizardCompleted` (see
  above).
- **`data/`** -- starts empty, no real backup of it ever existed. This
  means the actual Jellyfin database (users, accounts, watch history,
  library definitions -- everything the setup wizard configures) starts
  genuinely fresh: the first real start after this port shows Jellyfin's
  normal "Welcome to Jellyfin!" setup wizard, same as any brand-new
  install would. Confirmed by exhaustively searching the entire Media
  backup drive (not just the one path checked initially) for any
  `jellyfin.db` -- none exists anywhere. Only the peripheral config files
  above (branding, network, encoding settings, one user's profile
  picture) were ever backed up; the actual database with real
  users/libraries/watch-history was not, on this machine, at any
  location found. Re-running the setup wizard once is unavoidable unless
  a real `jellyfin.db` backup turns up somewhere else.
- **Library storage** (`libraries/media-{movies,shows,anime,music,
  audiobooks,books,photos}`) -- fixed from the old, stale `/mnt/Storage`
  (never a real mount point on this machine) to the real mount,
  `/run/media/<user>/Storage` -- same class of bug already found and
  fixed for Stash earlier this session.
- **`libraries/media-selfhosted`** -- moved to
  `~/Images/SelfHosted/Jellyfin/artwork` (a subdirectory, not the vault
  service dir's root) specifically to avoid colliding with the new
  `config`/`data` vault entries above, which didn't exist as vault
  entries in the old setup (the old `media-selfhosted` pointed at the
  bare `~/Images/SelfHosted/Jellyfin` root).

The `data|.../SelfHosted/SearXNG/data`-style scenario doesn't apply here
-- every real entry in the old `library.sh` was ported, nothing declared-
but-unused was found in it.

## Workflows

**Bump the version**: `systemctl start self-hosted-jellyfin@update:apply`
(writes directly), or `@update` first to see the diff. Then rebuild,
restart.

**Repair a library after a path change**:
`systemctl start self-hosted-jellyfin@rescan` -- stops Jellyfin, cleans
stale ancestor rows, restarts, triggers a scan. Destructive to those
stale rows specifically (by design), not a routine action.

**Switch themes / pick up a new build**: drop a new `theme.css` under
`Dotfiles/Themes/Jellyfin/<name>/`, point `theme.cssPath` at it in
`config/self-hosted/jellyfin.nix`, rebuild, restart -- `postStart`'s
theme sync re-embeds the new content into `CustomCss` on that restart.

**Set up a stable admin API key** (recommended once, not required):
create one via Dashboard -> API Keys -> +, then
`secrets self-hosted jellyfin`, enter `JELLYFIN_API_KEY=<the key>`,
`systemctl restart self-hosted-jellyfin`.

**Full teardown**: set `enabled = false` in
`config/self-hosted/jellyfin.nix`, rebuild --
`mkTeardownActivationScript` removes `cache`/`transcode`/`log` only
(`teardownPaths`). `config`/`data`/every `libraries/<name>` entry are
storage-backed and never touched by this. Flip `enabled` back to `true`
and rebuild again to reinstall.
