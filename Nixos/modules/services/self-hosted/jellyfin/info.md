# Jellyfin -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./jellyfin.nix`. Implementation detail
pieces: `./lib/{package,update,rescan,plugins-sync,wait-for-api}.nix`,
`./lib/theme/{server,sync}.nix`.
Real values: `Nixos/config/self-hosted/jellyfin.nix`.
Real theme source: `Dotfiles/Themes/Jellyfin/ElegantFin/theme.css` --
same top-level convention as every other themed app in this repo, not
under `Nixos/config/`.

Binary comes from a pure Nix fetch (`lib/package.nix`), same shape as
Ollama/Stash -- no venv, no FHS sandbox. A self-contained .NET publish,
patched with `autoPatchelfHook` for its native library dependencies (see
"Two real library bugs" below for the two that weren't caught by that
alone). Real, working machinery beyond the live service itself: a
separate theme-server sidecar unit + a live branding-API push, and a
declarative (currently-empty) plugin-repo/plugin-install mechanism --
both need Jellyfin's own REST API, so both run in `postStart`, not
`preStart`.

## Options (`vars.selfHosted.jellyfin`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service, theme server (if `themeServer.enable`), and actions all exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" below). |
| `dataDir` | str | `~/Applications/Networking/Jellyfin` | Plain base dir -- real writable subdirs `cache`/`transcode`/`log` live directly here; `config`/`data`/`libraries/<name>` are all storage-backed symlinks (see `storage`). |
| `autoStart` | bool | `true` | Same meaning as every other service here. Currently `false` in this machine's real config. |
| `version` | str | *required* | Jellyfin release version to pin. |
| `hash` | str | *required* | SRI sha256 of that version's linux amd64 release tarball. |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process -- `DOTNET_GCConserveMemory`/`DOTNET_EnableDiagnostics` are real, confirmed-used (ported from the old `launch.sh`). `JELLYFIN_LOG_LEVEL` was declared there too but confirmed dead. |
| `storage` | listOf `{src,dest}` | `[ ]` | Two different kinds of real data behind the same mechanism -- see "Real, migrated data" below for the full list and why it's shaped this way. |
| `requireMounts` | listOf str | `[ ]` | Paths checked as mountpoints before `preStart` runs. Real config needs both the Casket vault and the external Storage drive. |
| `teardownPaths` | listOf str | `[ ]` | Non-empty on purpose (ComfyUI's shape) -- `["cache" "transcode" "log"]`. See default.nix's own comment: nested storage entries (`libraries/<name>`) aren't correctly recognized by the default "everything but storage" rule, which only matches top-level basenames. |
| `fdLimit` | nullOr int | `65536` | `LimitNOFILE` on the live unit -- real, ported from the old `runtime.sh`'s `ulimit -n`. Required adding a new `limitNoFile` param to `mkSelfHostedService` itself (opt-in, `null` by default, no effect on any other service). |
| `ffmpeg` | nullOr package | `null` | Package providing `bin/ffmpeg`, passed to Jellyfin's real `--ffmpeg` flag. `null` = `pkgs.jellyfin-ffmpeg` (resolved in `jellyfin.nix`, not here). Deliberately not "system ffmpeg on PATH" (the old `deps.sh`'s approach). |
| `themeServer.enable` | bool | `true` | Master switch for the whole theme mechanism. |
| `themeServer.themeDir` | nullOr path | `null` | Directory containing `theme.css` to serve -- a directory, not a direct file path (see the option's own doc comment for why: a `path` pointing straight at one file gets copied into the store standalone, with no meaningful parent to serve). |
| `themeServer.bindAddress` | str | `"0.0.0.0"` | Address the CORS static file server binds to. |
| `themeServer.port` | port | `6055` | Port the CORS static file server listens on. |
| `themeServer.publicHostname` | str | `"jellyfin.local"` | Hostname embedded in the `@import` URL pushed into Jellyfin's branding config -- deliberately not `localhost` (fetched by each client's own browser, not the server). Needs real mDNS/hosts resolution (this machine's own pmg setup), out of Nix's scope. |
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

## The theme server needs an explicit `Wants=`/`After=`, not just `PartOf=`

`PartOf=self-hosted-jellyfin.service` on the theme server unit only
propagates *stop*/*restart* (confirmed: starting jellyfin left the theme
server dead until manually started) -- `Wants=`/`After=` on the *main*
service, pointing at the theme unit, is what's actually needed to make
starting jellyfin also start it, matching the old `run_start()`'s
"start jellyfin, then start theme-server" ordering. Both directions are
wired in `jellyfin.nix`.

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
  `postStart`: theme branding sync (only if `themeServer.enable` and
  `themeDir` set), then plugin installs (only if `cfg.plugins != [ ]`) --
  both bounded-poll-until-ready first (`lib/wait-for-api.nix`), both
  gracefully skip (exit 0, don't fail the service) if no admin API key
  exists yet. `LimitNOFILE=65536`, `TimeoutStartSec=infinity`, same as
  every service here.
- `self-hosted-jellyfin-theme.service` -- the theme server sidecar (see
  above for the `Wants=`/`After=`/`PartOf=` relationship). Only exists at
  all if `themeServer.enable && themeServer.themeDir != null`.
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
- **`data/`** -- starts empty, no real backup of it ever existed.
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

**Add another theme**: drop a new `theme.css` under
`Dotfiles/Themes/Jellyfin/<name>/`, point `themeServer.themeDir` at it in
`config/self-hosted/jellyfin.nix`, rebuild, restart (this restarts both
the live service and the theme server, since they're `Wants=`/`After=`-
linked).

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
