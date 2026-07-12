# Ollama -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./ollama.nix`. Implementation detail
pieces: `./lib/{package,sync,update}.nix`. Real values:
`Nixos/config/self-hosted/ollama.nix`.

Binary comes from a pure `fetchurl`-style Nix derivation (`lib/package.nix`) --
no venv, no FHS sandbox, no manual install step. `nixos-rebuild switch`
alone is enough to get a working `ollama` binary; nothing needs to be
manually installed afterward. The only manual action left is
`update`/`update:apply` -- checking upstream for a newer release.

## Options (`vars.selfHosted.ollama`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service + actions exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" below), not just absent. |
| `dataDir` | str | `~/Applications/Networking/Ollama` | Where pulled model blobs live. Drives `OLLAMA_MODELS`. Plain, not vault-backed. |
| `autoStart` | bool | `true` | `false` = exists, `systemctl start`-able, but not on boot/rebuild. Currently `false` in this machine's real config. |
| `version` | str | *required* | Ollama release version to pin, e.g. `"0.31.2"`. |
| `hash` | str | *required* | SRI sha256 of that version's `ollama-linux-amd64.tar.zst`. Get a new one with `nix-prefetch-url --type sha256 <url>` then `nix hash convert --to sri`. |
| `environment` | attrsOf str | `{ }` | Plain passthrough to the live process -- `OLLAMA_HOST`, `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_KEEP_ALIVE`, `CUDA_VISIBLE_DEVICES`, etc. |
| `host` | nullOr str | `null` | Optional typed override -- if set (with or without `port`), `ollama.nix` constructs a fresh `OLLAMA_HOST` that wins over whatever's in `environment.OLLAMA_HOST`. `null` = no override, `environment.OLLAMA_HOST` (the plain passthrough way, unchanged) applies as-is. Not the primary mechanism, an optional one on top of it. |
| `port` | nullOr port | `null` | Same override, the port half. Whichever of `host`/`port` you *don't* set falls back to `"0.0.0.0"`/`11434` (Ollama's own conventional defaults), not to whatever's already in `environment.OLLAMA_HOST` -- setting either one means overriding the whole value, not patching half of an existing string. |
| `models` | listOf str | `[ ]` | Declared models, e.g. `"llama3.1:8b"`. Reconciled automatically every service start via `postStart`, once the server is confirmed up -- never during rebuild/activation itself. |
| `storage` | listOf `{src,dest}` | `[ ]` | `src` relative to `dataDir` -> symlink to absolute `dest`, applied via `systemd.tmpfiles.rules`. |
| `teardownPaths` | listOf str | `[ ]` | Paths, relative to `dataDir`, removed when `enabled = false`. Empty here (the safe default) since `dataDir` holds nothing but pulled model blobs -- "everything but storage" is correct as-is. See `../docs/architecture.md`'s `mkTeardownActivationScript` section. |

## systemd units

- `self-hosted-ollama.service` -- the live `ollama serve` process.
  `Restart=on-failure`, `TimeoutStartSec=infinity` (a slow first-run
  install/download should never be killed by systemd's default 90s start
  timeout -- see ComfyUI's `info.md` for the real incident this was
  found from, same fix applies generically to every service). `postStart`
  runs `lib/sync.nix`'s script right after the process forks -- see "Sync
  behavior" below for why it's postStart and not preStart.
- `self-hosted-ollama@update` -- checks `ollama/ollama`'s GitHub releases
  for something newer than `version`. **Print-only** -- never edits
  `config/self-hosted/ollama.nix` itself. Read the new `version`/`hash`
  from `journalctl -u self-hosted-ollama@update`, paste them in by hand,
  rebuild.
- `self-hosted-ollama@update:apply` -- same check, but if something's
  newer, `sed`-writes the new `version`/`hash` straight into
  `config/self-hosted/ollama.nix` instead of just printing them. Still
  doesn't rebuild or restart anything -- that's still a deliberate,
  separate step.

There is no separate uninstall action -- see `../docs/architecture.md`'s
"No uninstall action" for why. Full teardown is driven by `enabled`
instead, see below.

## Sync behavior (`./lib/sync.nix`)

Runs as `postStart`, not `preStart`, because it goes through the live
process's own HTTP API (`ollama list`/`ollama pull`/`ollama rm`), which
isn't up the instant the binary forks -- `ExecStartPost` fires right
after fork/exec, with no guarantee the server is actually accepting
requests yet. `sync.nix` polls `ollama list` in a bounded loop (up to 30s)
before doing any real work, and fails loudly if the server never comes up
in that window rather than silently skipping reconciliation.

Reads `$OLLAMA_MODELS_DECLARED` (space-separated, set from `cfg.models` by
`ollama.nix`), diffs it against `ollama list`'s actual output:
- Declared but not installed -> `ollama pull <model>`.
- Installed but not declared -> `ollama rm <model>`.

Runs on **every** service start, not just the first -- idempotent, a
no-op diff costs one `ollama list` call.

## Workflows

**Add/remove a model**: edit the `models` list in
`Nixos/config/self-hosted/ollama.nix`, rebuild, restart
`self-hosted-ollama.service` -- `postStart` handles both directions on
that same restart: adding pulls it, removing actually deletes the blob
(unlike ComfyUI's models, there's no separate add/cleanup split here --
Ollama's own storage format makes "installed but undeclared" cheap and
safe to just remove).

**Bump the Ollama version**: `systemctl start self-hosted-ollama@update:apply`
(writes `version`/`hash` into `config/self-hosted/ollama.nix` directly),
or `@update` first if you want to see the diff before it lands. Then
rebuild, restart `self-hosted-ollama.service`. No lockfile, no venv -- the
new binary is just a different Nix store path.

**Full teardown**: set `enabled = false` in `config/self-hosted/ollama.nix`,
rebuild -- `mkTeardownActivationScript` (`../self-hosted.nix`) removes
everything under `dataDir` (all pulled model blobs) automatically as part
of that same rebuild's activation, no manual action needed. `storage`
entries (empty by default here) are never touched by this. Flip `enabled`
back to `true` and rebuild again to reinstall from the same declared
`models` list.
