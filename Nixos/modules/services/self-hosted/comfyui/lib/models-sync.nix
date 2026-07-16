{ lib, dataDir, activeModels }:

# Model fetch/reconciliation, run every service start via preStart. Split
# out of comfyui.nix once that file grew past ~480 lines -- self-contained
# (nothing outside this file needs its internals beyond the one script it
# exposes).

let
  # Extension -> minimum byte size, ported from the old deps.sh's
  # EXPORT_ERROR_CHECK (KB there, bytes here) -- catches truncated/failed
  # downloads that still produced a file, before a later sync silently
  # treats them as "already have it".
  minSizeTable = {
    pth = 10000 * 1000;
    safetensors = 10000 * 1000;
    bin = 10000 * 1000;
    ckpt = 100000 * 1000;
    py = 100 * 1000;
    json = 10 * 1000;
    txt = 10 * 1000;
  };
  minSizeCase = lib.concatStrings (lib.mapAttrsToList
    (ext: bytes: ''"${ext}") min_size=${toString bytes} ;;
'')
    minSizeTable);

  # Space-separated (not newline-separated) so it survives being carried
  # as a plain systemd Environment= value -- same convention Ollama's
  # OLLAMA_MODELS_DECLARED uses and for the same reason. None of the
  # declared urls/targets contain a literal space (checked). Only
  # activeModels -- syncModelsScript (run every service start, via
  # preStart) fetches exactly the installed subset and trims disk down to
  # exactly that same subset, both directions in one script.
  declaredModels = lib.concatMapStringsSep " "
    (m: "${m.type}|${m.url}|${m.target}")
    activeModels;

  # Both directions in one script -- fetch every declared-but-missing
  # model, then remove any file under dataDir/models that isn't backing a
  # currently-installed one. Used to be two separate actions
  # (sync/cleanup, matching the old plugins.sh/cleanup.sh split), merged
  # once the store/installed split made "declared list shrinks" mean
  # "deliberately deactivated, pin still safe in modelStore" rather than
  # "oops, lost the pin" -- removal stopped being the one-way trip that
  # split was originally guarding against.
  syncModelsScript = ''
    set -euo pipefail
    count=0
    declared_models="${declaredModels}"
    for entry in $declared_models; do
      IFS='|' read -r type url target <<< "$entry"
      dest="${dataDir}/$target"
      mkdir -p "$(dirname "$dest")"

      header=""
      case "$type" in
        hf) [ -n "''${HF_TOKEN:-}" ] && header="Authorization: Bearer $HF_TOKEN" ;;
        civitai) [ -n "''${CIVITAI_TOKEN:-}" ] && header="Authorization: Bearer $CIVITAI_TOKEN" ;;
      esac

      if [ -f "$dest" ]; then
        ext="''${dest##*.}"
        min_size=0
        case "$ext" in
        ${minSizeCase}
        esac
        size="$(stat -c%s "$dest")"
        if [ "$min_size" -gt 0 ] && [ "$size" -lt "$min_size" ]; then
          echo "[corrupt] removing $target (''${size}B < ''${min_size}B)" >&2
          rm -f "$dest"
        else
          # The min_size floor above only catches obviously-tiny garbage
          # (10MB) -- nowhere near enough to catch a multi-GB download that
          # stalled partway (found this the hard way: a truncated ~300MB
          # civitai fetch of a 6.47GB file passed that floor and got
          # silently treated as complete on every restart after). Ask the
          # server what the real size actually is (HEAD, following
          # redirects same as the real fetch does) and compare -- a
          # mismatch means the local file is stale/incomplete, not that a
          # new version was published (these URLs are pinned to one exact
          # file/version each, never re-point at different content).
          # git entries never reach here (dest is a directory, "-f" is
          # already false for those) so no per-type branch needed below.
          if [ -n "$header" ]; then
            remote_size="$(curl -sI -L --max-time 15 -A "Mozilla/5.0" -H "$header" "$url" 2>/dev/null | tr -d '\r' | grep -i '^content-length:' | tail -1 | cut -d' ' -f2)"
          else
            remote_size="$(curl -sI -L --max-time 15 -A "Mozilla/5.0" "$url" 2>/dev/null | tr -d '\r' | grep -i '^content-length:' | tail -1 | cut -d' ' -f2)"
          fi
          case "$remote_size" in
          "" | *[!0-9]*)
            # No usable Content-Length back (HEAD unsupported, network
            # hiccup, whatever) -- can't compare, fall back to trusting
            # the floor check like before rather than force a redundant
            # re-download on every restart.
            echo "[skip] $target"
            count=$((count + 1))
            continue
            ;;
          "$size")
            echo "[skip] $target"
            count=$((count + 1))
            continue
            ;;
          *)
            echo "[stale] removing $target (local ''${size}B != remote ''${remote_size}B)" >&2
            rm -f "$dest"
            ;;
          esac
        fi
      fi

      case "$type" in
      git)
        echo "[git] $target"
        git clone --depth=1 "$url" "$dest"
        ;;
      *)
        echo "[download] $target"
        if [ -n "$header" ]; then
          aria2c --dir="$(dirname "$dest")" --out="$(basename "$dest")" --continue=true -x4 -s4 \
            --header="$header" --user-agent="Mozilla/5.0" "$url" \
            || curl -L -f -A "Mozilla/5.0" -H "$header" -o "$dest" "$url"
        else
          aria2c --dir="$(dirname "$dest")" --out="$(basename "$dest")" --continue=true -x4 -s4 \
            --user-agent="Mozilla/5.0" "$url" \
            || curl -L -f -A "Mozilla/5.0" -o "$dest" "$url"
        fi
        ;;
      esac

      if [ -f "$dest" ]; then
        ext="''${dest##*.}"
        min_size=0
        case "$ext" in
        ${minSizeCase}
        esac
        size="$(stat -c%s "$dest")"
        if [ "$min_size" -gt 0 ] && [ "$size" -lt "$min_size" ]; then
          echo "[fail] too small: $target" >&2
          rm -f "$dest"
          continue
        fi
      fi

      count=$((count + 1))
    done
    echo "[sync] $count fetched/kept"

    declared_file="$(mktemp)"
    trap 'rm -f "$declared_file"' EXIT
    for entry in $declared_models; do
      IFS='|' read -r _ _ target <<< "$entry"
      echo "${dataDir}/$target" >> "$declared_file"
    done

    removed=0
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      if ! grep -qxF "$file" "$declared_file"; then
        echo "[remove] $file"
        rm -f "$file"
        removed=$((removed + 1))
      fi
    done < <(find "${dataDir}/models" -type f 2>/dev/null)
    echo "[sync] $removed removed"
  '';
in
syncModelsScript
