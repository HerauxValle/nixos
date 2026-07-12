# TODO

1. Migrate services (easiest to hardest, per ~/Scripts/Self-hosted/<Service>/COMMANDS.md)
        - [ ]FileBrowser - single static binary, sqlite db bootstrap, one port, one root dir. No venv, no external services.
        - [ ]SearXNG - pip venv + FHS sandbox (same shape as OpenWebUI), settings.yml scaffold, hooks, storage symlinks. No external services.
        - [ ]Jellyfin - downloaded release tarball (same shape as Ollama), plus plugins/hwaccel/theme-server/rescan/library-symlink surface.
        - [ ]Immich - compiled server+web build, separate ML sidecar venv, plus external system services (Postgres w/ pgvector, Redis). Hardest, most moving parts.
2. Test selfhosted services
        - [x]ComfyUI - hardened already
        - [x]OpenWebUI - fixed stale pre-alembic config table (old key/value schema blocked startup), migrated real Jun 29 settings into new schema, old data kept as backup tables. Tool-server connection error in logs is user's own config (unrelated tool server not running), harmless.
        - [x]Stash - hardened, fixed ownership + missing ffmpeg + missing library mount
        - [x]Ollama - fixed missing gawk on postStart's PATH (start-limit-hit), model pull + generate confirmed working
        - [ ]FileBrowser
        - [ ]SearXNG
        - [ ]Jellyfin
        - [ ]Immich
3. Add more detailed documentation with clear source code references
4. Rename repo to "empyrean-shell"
5. Verify Comfyui's nodes are independent and installation only happens when in installed
6. Verify reproducability
7. ...
