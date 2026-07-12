# TODO

1. Migrate services (easiest to hardest, per ~/Scripts/Self-hosted/<Service>/COMMANDS.md)
        - [x]FileBrowser - pinned own release (not nixpkgs, per consistency w/ other services), BoltDB (not sqlite as assumed), recovered real filebrowser.db from Media backup drive's ~/.config/filebrowser and moved it into the SelfHosted vault (was never vault-backed originally), root faithfully kept as full $HOME per old config
        - [x]SearXNG - actually a git-clone-pinned source (no pip package upstream) + FHS venv, not OpenWebUI's simpler shape; settings.yml is a single-file storage symlink into the vault (recovered from Scripts/, never vault-backed before); fixed non-functional secret_key placeholder (real SEARXNG_SECRET env var override, native to searxng); themes moved to Dotfiles/Themes/Searxng/ (not Nixos/config/) per correction; fixed ln -sfn silently failing against stock searx/templates/simple/ (real dir, not symlink) so the hand-edited simple theme actually takes effect now
        - [x]Jellyfin - own-pinned .NET release tarball, needed autoPatchelfHook + dontStrip=true (default strip corrupts managed .dll assemblies) + LD_LIBRARY_PATH wrapper for icu+openssl (dlopen'd by SONAME, not caught by autoPatchelf); real theme-server sidecar unit (CORS static server + live branding-API push, ElegantFin theme frozen into Dotfiles/Themes/Jellyfin/); plugins mechanism built (empty by default); confirmed dead: hwaccel vars, host/port vars (jellyfin self-manages via network.xml); real secrets wired via existing Scripts/Secrets/cmd/self-hosted.sh; fixed a real framework bug (nested storage src paths like libraries/media-movies got auto-created root-owned by tmpfiles, now fixed generically in mk-self-hosted-service.nix); fixed recovered system.xml's IsStartupWizardCompleted=true crashing against a fresh db (SQLite __EFMigrationsHistory error)
        - [ ]Immich - compiled server+web build, separate ML sidecar venv, plus external system services (Postgres w/ pgvector, Redis). Hardest, most moving parts.
2. Test selfhosted services
        - [x]ComfyUI - hardened already
        - [x]OpenWebUI - fixed stale pre-alembic config table (old key/value schema blocked startup), migrated real Jun 29 settings into new schema, old data kept as backup tables. Tool-server connection error in logs is user's own config (unrelated tool server not running), harmless.
        - [x]Stash - hardened, fixed ownership + missing ffmpeg + missing library mount
        - [x]Ollama - fixed missing gawk on postStart's PATH (start-limit-hit), model pull + generate confirmed working
        - [x]FileBrowser - verified: service active, 0 restarts, HTTP 200, /health OK, /api/settings correctly 401s (real recovered auth in effect, not a fresh install)
        - [x]SearXNG - verified: service active, 0 restarts, HTTP 200, real search returns results, both themes (simple/adversarial) confirmed correctly symlinked and serving custom content
        - [x]Jellyfin - verified: both services active, 0 restarts, HTTP 200 on Jellyfin + theme server, real db migrated cleanly, ffmpeg found, theme @import pushed to branding.xml automatically on start
        - [ ]Immich
3. Add more detailed documentation with clear source code references
4. Rename repo to "empyrean-shell"
5. Verify Comfyui's nodes are independent and installation only happens when in installed
6. Verify reproducability
7. ...
