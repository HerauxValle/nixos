<!-- &desc: "gamdl-wrapper reference -- options, one-time manual staging steps (APK extraction, login), day-to-day usage with gamdl --use-wrapper." -->

# gamdl-wrapper

A local `wrapper-v2` daemon (https://github.com/glomatico/wrapper-v2) that
gives `gamdl` (`config/software/packages/custom/gamdl.nix`) a FairPlay
decrypt path for **lossless ALAC** downloads. AAC (`aac-web`, the gamdl
default) never needs this -- only reach for it when you specifically want
lossless.

## Options (`config.vars.services.gamdlWrapper`)

| Option | Default | Notes |
| --- | --- | --- |
| `enabled` | `false` | Restages source + installs the systemd user unit + `gamdl-wrapper-stage-libs`. Does **not** by itself make lossless work -- Apple's libs still need staging (below). |
| `autoStart` | `false` | Boot-start the daemon. Off by default; it's only needed while actually doing a lossless download. |
| `srcDir` | `~/.local/share/gamdl-wrapper` | Restaged from the pinned Nix store copy on every rebuild (additive rsync, no `--delete`). `rootfs/system/lib64/` and `data/` are real runtime state and are never touched by that restaging. |
| `httpPort` | `8880` | wrapper-v2's HTTP control API. |
| `decryptPort` | `10020` | wrapper-v2's raw TCP FPS decrypt port. |
| `targetArch` | `x86_64` | Must match the APK split you stage in. |

## One-time setup (manual -- can't be made declarative)

wrapper-v2 needs Apple's own Android Apple Music native libraries, which
aren't redistributable and can't be fetched by Nix. You have to supply
them yourself:

1. **Get the Apple Music Android APK.** The pinned library hashes in
   `LIBS_VERSION.json` are for build `3.6.0-beta 1109`; a different
   version will fail the hash check (pass `--ignore-hash` to skip it --
   the libs still need to actually be ABI-compatible, so this is a
   "might work" fallback, not a guarantee). Waydroid is already set up
   on this machine (`~/.local/share/waydroid/`) -- install Apple Music
   from the Play Store inside it, then pull the APK out
   (`waydroid app list` / `adb pull`, or a Play Store APK extractor app),
   or use an `.apkm` bundle from an APK mirror if you already have the
   exact build.

2. **Stage the libs:**
   ```
   gamdl-wrapper-stage-libs /path/to/apple-music.apk
   ```
   This runs wrapper-v2's own `tools/extract-libs.sh` against
   `srcDir/rootfs/system/lib64`, verifying each `.so` against
   `LIBS_VERSION.json` for `targetArch`. Add `--ignore-hash` if you're on
   a different Apple Music build and accept the risk.

3. **Start the daemon:**
   ```
   systemctl --user start gamdl-wrapper
   curl http://127.0.0.1:8880/health
   ```
   `runtime.playback_ready: true` means Apple's libs loaded correctly.

4. **Log in.** `gamdl --use-wrapper` drives `/login`/`/login/2fa`
   automatically and will prompt for your Apple ID + password (use an
   app-specific password: https://appleid.apple.com -> Sign-In and
   Security -> App-Specific Passwords) and, if needed, a 2FA code, the
   first time it needs an authenticated session. After that,
   `WRAPPER_RESTORE_SESSION=1` (wrapper-v2's default) reuses the cached
   session from `srcDir/data/` on daemon restart -- no repeated login.

## Day-to-day usage

```
systemctl --user start gamdl-wrapper   # only while you're doing a lossless download
gamdl --use-wrapper --wrapper-url http://127.0.0.1:8880 \
      --wrapper-decrypt-port 10020 \
      --song-codec-priority alac <URL>
systemctl --user stop gamdl-wrapper    # optional -- it's idle-cheap, but no reason to leave it up
```

`~/.gamdl/config.ini`'s `song_codec_piority` can stay `alac` -- gamdl only
needs `--use-wrapper` (or `use_wrapper = true` in the config) to actually
route through this daemon instead of the local `.wvd` CDM path.

## Update

No `update`/`update:apply` action -- this isn't wired into the
self-hosted framework (see `gamdl-wrapper.nix`'s top comment for why).
To bump the pinned `rev`, get a new commit SHA from
https://github.com/glomatico/wrapper-v2/commits/main, then:
```
nix-prefetch-url --unpack https://github.com/glomatico/wrapper-v2/archive/<sha>.tar.gz
nix hash convert --hash-algo sha256 --to sri <the printed hash>
```
and update both `rev` and `hash` in `gamdl-wrapper.nix`.
