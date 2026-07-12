# QBitTorrent -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./qbittorrent.nix`. Implementation
detail: `./lib/update.nix`. Real values:
`Nixos/config/self-hosted/qbittorrent.nix`. Shared helper:
`../lib/mk-from-native/services.nix` (`mkFromNativeService`, same one
Immich uses).

Not in the original 8-service migration scope -- the old
`~/Scripts/Self-hosted/QBitTorrent/main.sh` was a bare `nohup`+PID-file
wrapper (auto-installs the system package, no real per-machine config of
its own). But a real prior install's actual config *was* found
mid-session, on a completely different mount than the old bash framework
ever referenced: `/run/media/herauxvalle/Media/Home/.config/qBittorrent/
qBittorrent.conf`. Read directly, not guessed -- every real value in
`config/self-hosted/qbittorrent.nix` is pinned against it.

## Why this wraps `services.qbittorrent` instead of building from scratch

`nixos/modules/services/torrent/qbittorrent.nix` (read in full before
writing this module) is a real, mature module: a dedicated system user,
full systemd hardening on the unit, typed `webuiPort`/`torrentingPort`
options, and a real freeform `serverConfig` submodule that maps directly
onto `qBittorrent.conf`. Same reasoning as Immich -- wrap it via
`mkFromNativeService`, don't rebuild what's already correct.

## Real INI keys -- confirmed by running qbittorrent-nox, not guessed

qBittorrent's own wiki (`Explanation-of-Options-in-qBittorrent`)
documents the GUI's Options dialog, not the real `qBittorrent.conf` key
names. Rather than guess, this session built `pkgs.qbittorrent-nox`
directly, ran it in a throwaway profile, logged into its real WebAPI
(the temporary admin password it prints on first run), set real
preferences through `POST /api/v2/app/setPreferences`, and read back the
resulting `qBittorrent.conf` to see exactly what landed -- then
cross-checked every one of them against the real recovered prior config
once it was found, which matched exactly:

- `[BitTorrent] Session\DefaultSavePath` -- completed-download path.
- `[BitTorrent] Session\TempPath` / `Session\TempPathEnabled` -- the
  incomplete/temp-download path and its enable flag.
- `[BitTorrent] Session\TorrentExportDirectory` /
  `Session\FinishedTorrentExportDirectory` -- copy every added torrent's
  `.torrent` file, vs. only once that download finishes.
- `[Preferences] WebUI\Address` -- bind-address override (not documented
  anywhere upstream that was found).
- `[LegalNotice] Accepted` -- required for qbittorrent-nox to actually
  start non-interactively at all; the module's own `serverConfig`
  example already shows this, confirmed necessary by testing without it
  first (the real binary just sits there waiting for interactive
  confirmation otherwise).

## Options (`vars.selfHosted.qbittorrent`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. No teardown mechanism -- same reasoning as Immich (real, potentially-irreplaceable paths, no dataDir shape to scope an automated teardown against). |
| `autoStart` | bool | `true` | `false` = exists, `systemctl start qbittorrent`-able, not on boot/rebuild. Overrides the wrapped module's own hardcoded `wantedBy` via `lib.mkForce`, same mechanism as Immich. Currently `false` in this machine's real config. |
| `profileDir` | str | *required* | `services.qbittorrent.profileDir`. Real value is vault-backed (`~/Images/SelfHosted/QBitTorrent`) -- fresh, the recovered real install lived on a completely different mount, not vault-backed there either. |
| `webuiPort` | port | `8080` | `services.qbittorrent.webuiPort`. Real value on this machine is `7080` (`WebUI\Port` in the recovered conf). |
| `host` | nullOr str | `null` | Optional override, mapped to `serverConfig.Preferences.WebUI.Address`. `null` = qBittorrent's own default (binds every interface) -- the recovered conf never set this key either, so `null` is the real prior value, not just a safe default. |
| `torrentingPort` | nullOr port | `null` | `services.qbittorrent.torrentingPort` if set. Real value on this machine is `1729` (`Session\Port` in the recovered conf). |
| `paths.save` | str | *required* | Mapped to `serverConfig.BitTorrent.Session.DefaultSavePath`. Real value is the external Storage drive's already-existing `Torrents/Library/` (3.5TB of real content). |
| `paths.temp` | nullOr str | `null` | Mapped to `serverConfig.BitTorrent.Session.TempPath` (+ `TempPathEnabled = true`, set automatically). `null` = incomplete downloads land directly in `paths.save`. Real value is `Torrents/Incomplete/`. |
| `paths.export` | nullOr str | `null` | Mapped to `serverConfig.BitTorrent.Session.TorrentExportDirectory` -- every added torrent's `.torrent` file, unconditionally. Real value is `Torrents/Database/`. |
| `paths.finished` | nullOr str | `null` | Mapped to `serverConfig.BitTorrent.Session.FinishedTorrentExportDirectory` -- only once that download finishes. Real value is `Torrents/Deprecated/`. |
| `requireMounts` | listOf str | `[ ]` | Real value needs both the SelfHosted vault (`profileDir`) and the external Storage drive (every `paths.*` entry). |
| `extraServerConfig` | attrsOf anything | `{ }` | Freeform escape hatch onto `serverConfig`, merged under the typed options above (`lib.recursiveUpdate cfg.extraServerConfig { ... }` -- the typed mapping always wins on key collisions). Real config ports several more non-secret preferences straight from the recovered conf this way -- see below. |

## Real data -- a real torrent library, matched against a real recovered config

`/run/media/<user>/Storage/Torrents/` already has real content
(confirmed by inspecting the drive directly), and every one of its four
subfolders was confirmed -- not guessed -- against the real recovered
`qBittorrent.conf`:

- `Library/` (**3.5TB**) -- `Session\DefaultSavePath`. Maps to `paths.save`.
- `Incomplete/` (empty) -- `Session\TempPath`. Maps to `paths.temp`.
- `Database/` -- `Session\TorrentExportDirectory` (every added torrent).
  Maps to `paths.export`.
- `Deprecated/` -- `Session\FinishedTorrentExportDirectory` (only once
  finished). Maps to `paths.finished`.

Before the recovered conf turned up, `Database`/`Deprecated` was a real
judgment call based only on the folder names -- and a real cross-check
against the two folders' actual file lists (58 of ~75 filenames shared,
13 present only in `Deprecated`) initially seemed to *contradict* it: a
"finished" export should logically always be a subset of an "on add"
export, since anything that finished was necessarily added first, and
that subset relationship didn't hold. Once the real conf was found, it
confirmed the original folder-name-based mapping was right anyway --
the file-list mismatch was just real-world mess (manual re-adds,
cleanup), not a sign of the wrong assignment. Documented here as a
reminder that a plausible-looking counter-signal isn't automatically
right either -- the actual config file was the only thing that settled
it for real.

`profileDir` itself starts genuinely empty on this machine -- the
recovered real install's actual profile lived under a different path
entirely (`/run/media/herauxvalle/Media/Home/.config/qBittorrent/`, not
`--profile`-based at all, just qBittorrent's own XDG default location on
that other mount). First start here creates a fresh profile from
scratch; only the *settings* were recovered, not the session/resume
state.

## `ProtectHome` -- same real conflict Immich already hit, same fix

`services.qbittorrent` hardcodes `ProtectHome = "yes"` on its own unit
-- since `profileDir` is vault-backed (under `/home`), this hides it
from the process entirely, the identical mount-namespace problem
Immich's `mediaLocation` hit. Fixed the same confirmed way:
`ProtectHome = "tmpfs"` + `BindPaths` reusing `requireMounts` directly
(`qbittorrent.nix`, same pattern as `immich.nix`). Every `paths.*` entry
lives under `/run/media/...`, not `/home` at all, so they're unaffected
by `ProtectHome` either way -- only `profileDir` needed the fix.

## `/run/media/<user>` traversal -- a genuinely different problem from Immich's, needed a real new mechanism

Fixing `ProtectHome` wasn't enough on its own here, unlike Immich:
`paths.save`/`temp`/`export`/`finished` all live under
`/run/media/<user>/Storage`, and that directory itself
(`/run/media/<user>`, **not** `Storage`) is `0750 root:root` (confirmed
via `stat`) -- the dedicated `qbittorrent` system user has zero
traversal rights into it, completely independent of whether the drive
is mounted or whether `ProtectHome` is fixed (`/run/media` isn't
`/home` at all, so `ProtectHome`/`BindPaths` never touches it). This is
the real, first actual caller for `../lib/acl-traversal/` -- see that
module's own `default.nix` for the general mechanism and exactly when
to reach for it on a future service.

Two real bugs found getting this working end to end, both from actually
starting the service and reading the resulting journal, not guessed:

- **First attempt**: appended the ACL grant directly onto
  `qbittorrent.service`'s own `preStart` (merged via `types.lines`,
  same mechanism `requireMounts`'s mount check already uses). Two
  problems: (1) ordering -- `types.lines` doesn't guarantee this
  module's contribution runs before `mk-from-native/services.nix`'s own
  mount check, so the mount check ran first and failed (`mountpoint`
  needs the same traversal rights the grant was about to provide) --
  fixed with `lib.mkBefore`, but that exposed (2) the real, underlying
  problem: `qbittorrent.service` itself has `PrivateUsers = true`
  (part of the wrapped module's own hardening, never touched here) --
  running `setfacl` *inside* that private user namespace hit a genuine
  UID-mapping artifact (`user:4294967295:...`, systemd's "unmapped
  outside UID" sentinel) that collided with the real
  `u:qbittorrent:...` entry being written, failing outright with
  "Malformed access ACL ... Duplicate entries".
- **Real fix**: a fully separate systemd oneshot unit
  (`acl-traversal-<unit>.service`, `../lib/acl-traversal/acl-traversal.nix`)
  with `Before=`/`RequiredBy=` on the target unit, running as plain
  root with none of `qbittorrent.service`'s own hardening -- root
  doesn't need any ACL grant to traverse anything, sidestepping the
  `PrivateUsers` problem entirely, and strict unit ordering (rather than
  `types.lines` priority) makes the sequencing unambiguous. Confirmed
  working end to end: `acl-traversal-qbittorrent.service` exits
  `0/SUCCESS`, then `qbittorrent.service`'s own mount check passes,
  then the live service starts clean.

## `profileDir` ownership -- a leftover from an earlier failed attempt, not the wrapped module's fault

A real, separate bug hit while debugging the above: `profileDir`
(`~/Images/SelfHosted/QBitTorrent`) and its own `qBittorrent/`
subdirectory ended up `root:root` on disk -- a side effect of an
earlier failed start (before the ACL fix existed) creating the path as
root. The wrapped module's own `systemd.tmpfiles.settings.qbittorrent`
rules (`d` type, on `profileDir/qBittorrent/` and
`profileDir/qBittorrent/config/`) only fix ownership *at creation
time* -- they don't correct already-wrong ownership on an existing
path, and don't cover `profileDir` itself at all. Fixed the same way as
Immich's `mediaLocation`: a recursive `Z` tmpfiles rule on `profileDir`,
every activation, idempotent (`qbittorrent.nix`).

## Default WebUI credentials -- not baked into Nix, deliberately

The recovered real conf has actual values for `WebUI\Username`
(`heraux.valle@gmail.com`), `WebUI\Password_PBKDF2` (a real hash), and
`WebUI\APIKey` -- none of them are ported into this module. `serverConfig`
always ends up as a `pkgs.writeText` derivation: world-readable in the
Nix store, and (since it's declared in `config/`, a git-tracked file)
committed to this repo's history. Unlike Immich's `secretsFile`, the
wrapped module has no external-file escape hatch for just this one
field -- there's no way to reference these three real values from Nix
without also leaking them. qbittorrent-nox itself already handles the
"no credentials configured" case cleanly: it generates a random
temporary admin password on first start and prints it to the unit's own
log (`journalctl -u qbittorrent`). Set a real username/password through
the WebUI itself after first start instead (the real prior username
above, if you want to match it) -- same "configure via the app's own
UI, don't bake credentials into Nix" precedent as every other service's
admin account.

## Real, non-secret preferences ported via `extraServerConfig`

Everything below came from the recovered conf too, but none of these
are individually consequential enough to deserve a dedicated typed
option (matches this session's own "don't generalize until a second
real need exists" rule) -- set directly in `config/self-hosted/
qbittorrent.nix`'s `extraServerConfig`:

- `BitTorrent.MergeTrackersEnabled = true`
- `BitTorrent.Session.AnonymousModeEnabled = true`
- `BitTorrent.Session.ConnectionSpeed = 100`
- `BitTorrent.Session.Encryption = 1`
- `BitTorrent.Session.GlobalUPSpeedLimit = 0`
- `BitTorrent.Session.IgnoreLimitsOnLAN = true`
- `BitTorrent.Session.MaxActiveDownloads = 2`
- `BitTorrent.Session.MultiConnectionsPerIp = true`
- `BitTorrent.Session.PieceExtentAffinity = true`
- `BitTorrent.Session.QueueingSystemEnabled = true`
- `BitTorrent.Session.SSL.Port = 49999`
- `BitTorrent.Session.StartPaused = false`
- `Core.AutoDeleteAddedTorrentFile = "Never"`
- `Preferences.General.Locale = "en"`

## systemd units

- `acl-traversal-qbittorrent.service` -- runs first (`Before=`/
  `RequiredBy=` on `qbittorrent.service`, see `../lib/acl-traversal/`),
  a plain-root oneshot granting the dedicated `qbittorrent` user
  traversal into `/run/media/<user>`. Not part of `qbittorrent.service`
  itself, deliberately -- see this file's own "`/run/media/<user>`
  traversal" section for why.
- `qbittorrent.service` -- built entirely by the wrapped
  `services.qbittorrent` module. `preStart` (from the wrapped module
  itself, when `serverConfig != {}`) writes the generated
  `qBittorrent.conf` before start. `mkFromNativeService`'s own
  `mountCheckUnits` appends the `requireMounts` check onto this same
  unit's `preStart` (NixOS's own `preStart` is a mergeable `types.lines`
  -- concatenates cleanly, doesn't replace the wrapped module's own
  contribution) -- only runs once `acl-traversal-qbittorrent.service`
  has already completed, so the mount check can actually see
  `/run/media/<user>/Storage`.
- `self-hosted-qbittorrent@update` / `@update:apply` -- fully
  independent of the units above (same `mkActionService` mechanism
  every service uses). Print-only, always -- no local version/hash to
  write, the package tracks nixpkgs' own `pkgs.qbittorrent-nox`.

## Workflows

**Set a real WebUI password**: check `journalctl -u qbittorrent` for the
printed temporary password on first start, log in as `admin`, set a
real username/password through the WebUI's own Options -> WebUI page
(the real prior username was `heraux.valle@gmail.com`, if you want to
match it).

**Check for a newer version**: `systemctl start
self-hosted-qbittorrent@update` -- prints current (nixpkgs-tracked)
vs. latest upstream, real network call to GitHub's API.

**Full teardown**: set `enabled = false`, rebuild -- `services.
qbittorrent.enable` goes off, no unit exists. `profileDir` and every
`paths.*` entry are never touched by this (no teardown mechanism
reaches them at all, same reasoning as Immich). Flip back to `true` and
rebuild to reinstall.
