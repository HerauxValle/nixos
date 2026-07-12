# Ollama -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./ollama.nix`. Package fetch: `./package.nix`.
Sync behavior: `./sync.nix`. Real values: `Nixos/config/self-hosted/ollama.nix`.

Binary comes from a pure `fetchurl`-style Nix derivation (`package.nix`) --
no venv, no FHS sandbox, no manual install step. `nixos-rebuild switch`
alone is enough to get a working `ollama` binary; nothing needs to be
manually installed afterward. The only manual action left is
`update`/`update:apply` -- checking upstream for a newer release.

## Options (`vars.selfHosted.ollama`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | `true` | Master switch. |
| `dataDir` | str | `~/Applications/Networking/Ollama` | Where pulled model blobs live. Drives `OLLAMA_MODELS`. Plain, not vault-backed. |
| `autoStart` | bool | `true` | `false` = exists, `systemctl start`-able, but not on boot/rebuild. |
| `version` | str | *required* | Ollama release version to pin, e.g. `"0.31.2"`. |
| `hash` | str | *required* | SRI sha256 of that version's `ollama-linux-amd64.tar.zst`. Get a new one with `nix-prefetch-url --type sha256 <url>` then `nix hash convert --to sri`. |
| `environment` | attrsOf str | `{ }` | Plain passthrough to the live process -- `OLLAMA_HOST`, `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_KEEP_ALIVE`, `CUDA_VISIBLE_DEVICES`, etc. |
| `models` | listOf str | `[ ]` | Declared models, e.g. `"llama3.1:8b"`. Reconciled automatically every service start via `postStart`, once the server is confirmed up -- never during rebuild/activation itself. |
| `storage` | listOf `{src,dest}` | `[ ]` | `src` relative to `dataDir` -> symlink to absolute `dest`, applied via `systemd.tmpfiles.rules`. |

## systemd units

- `self-hosted-ollama.service` -- the live `ollama serve` process.
  `Restart=on-failure`. `postStart` runs `sync.nix`'s script right after
  the process forks -- see "Sync behavior" below for why it's postStart
  and not preStart.
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

There is no uninstall action. See `../docs/architecture.md`'s "No
uninstall action" for why -- short version: model reconciliation is
already automatic, and the binary is just a Nix store path GC already
handles.

## Sync behavior (`./sync.nix`)

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

**Full teardown**: no scripted action, deliberately -- `rm -rf dataDir`
by hand if you actually want to wipe pulled model blobs.
