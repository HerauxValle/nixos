# Ollama -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./ollama.nix`. Package fetch: `./package.nix`.
Sync behavior: `./sync.nix`. Real values: `Nixos/config/self-hosted/ollama.nix`.

Binary comes from a pure `fetchurl`-style Nix derivation (`package.nix`) --
no venv, no FHS sandbox, no `@install` action. `nixos-rebuild switch` alone
is enough to get a working `ollama` binary; nothing needs to be manually
installed afterward.

## Options (`vars.selfHosted.ollama`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | `true` | Master switch. |
| `dataDir` | str | `~/Applications/Networking/Ollama` | Where pulled model blobs live. Drives `OLLAMA_MODELS`. Plain, not vault-backed. |
| `autoStart` | bool | `true` | `false` = exists, `systemctl start`-able, but not on boot/rebuild. |
| `version` | str | *required* | Ollama release version to pin, e.g. `"0.31.2"`. |
| `hash` | str | *required* | SRI sha256 of that version's `ollama-linux-amd64.tar.zst`. Get a new one with `nix-prefetch-url --type sha256 <url>` then `nix hash convert --to sri`. |
| `environment` | attrsOf str | `{ }` | Plain passthrough to both the live process and the sync unit -- `OLLAMA_HOST`, `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_KEEP_ALIVE`, `CUDA_VISIBLE_DEVICES`, etc. |
| `models` | listOf str | `[ ]` | Declared models, e.g. `"llama3.1:8b"`. Reconciled only by `@sync`, never automatically. |
| `storage` | listOf `{src,dest}` | `[ ]` | `src` relative to `dataDir` -> symlink to absolute `dest`, applied via `systemd.tmpfiles.rules`. |

## systemd units

- `self-hosted-ollama.service` -- the live `ollama serve` process. `Restart=on-failure`.
- `self-hosted-ollama@install` -- no-op, prints a note. The binary is a
  plain Nix store path (`package.nix`), already there after any rebuild
  -- exists purely so `@install` is valid on every self-hosted service.
- `self-hosted-ollama@sync` / `@sync:models` -- identical, `:models` is
  just an alias for consistency with the other services' `sync:<target>`
  form; Ollama only ever had one syncable category.
- `self-hosted-ollama@uninstall` -- removes `dataDir` (pulled model
  blobs) except anything a `storage` entry covers. Recoverable: re-run
  `@sync` with the same `models` list to get them back. Never touches
  the Nix store -- that's garbage collection's job (`pacnix orphaned`).
- `self-hosted-ollama@uninstall:data` -- tier 1 plus whatever `storage`
  entries actually point at (none by default). Not recoverable.
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

## Sync behavior (`./sync.nix`)

Reads `$OLLAMA_MODELS_DECLARED` (space-separated, set from `cfg.models` by
`ollama.nix`), diffs it against `ollama list`'s actual output:
- Declared but not installed -> `ollama pull <model>`.
- Installed but not declared -> `ollama rm <model>`.

Runs against the *live* `self-hosted-ollama` service over its local API --
the service must already be running for `@sync` to work.

## Workflows

**Add/remove a model**: edit the `models` list in
`Nixos/config/self-hosted/ollama.nix`, rebuild, then
`systemctl start self-hosted-ollama@sync`. Adding pulls it; removing
actually deletes the blob on that same sync run (unlike ComfyUI's models,
there's no separate add/cleanup split here -- Ollama's own storage format
makes "installed but undeclared" cheap and safe to just remove).

**Bump the Ollama version**: `systemctl start self-hosted-ollama@update:apply`
(writes `version`/`hash` into `config/self-hosted/ollama.nix` directly),
or `@update` first if you want to see the diff before it lands. Then
rebuild, restart `self-hosted-ollama.service`. No lockfile, no venv -- the
new binary is just a different Nix store path. `@install` has nothing to
do with this -- it's a no-op, not a real action here.

**Full teardown**: `systemctl start self-hosted-ollama@uninstall:data`
(no meaningful difference from plain `@uninstall` today, since `storage`
is empty by default -- becomes relevant if a `storage` entry is ever
added).
