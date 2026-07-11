{ lib, pkgs }:

# Shared builder every per-service module (./ollama, ./comfyui, ...) calls
# for the part that's genuinely identical across all of them: a live
# systemd unit, plus a manual-only reconciliation oneshot for services that
# need one. Each service module owns everything actually specific to it
# (its own typed options, its own package/fetch logic, its own
# reconciliation script content) and calls these with just the handful of
# values that differ. Adding a new service means writing one subfolder
# module against this, not a new engine -- this file is deliberately the
# only place the "how" of running a systemd unit is written.
#
# Plain function library, not a NixOS module itself (no `config`/`options`)
# -- imported directly by each service subfolder: `import ../self-hosted.nix
# { inherit lib pkgs; }`.

rec {

  # The live process. Restart=on-failure replaces the old bash framework's
  # nohup+PID-file+kill-loop entirely.
  mkSelfHostedService =
    { name
    , execStart
    , user
    , packages ? [ ]
    , environment ? { }
    , preStart ? [ ]
    , storage ? [ ]
    , dataDir ? null
    , autoStart ? true
      # false (default) is the safe choice: dataDir's existence isn't
      # Nix's business unless it's told it's safe to assume. true only
      # for services whose dataDir isn't gated by anything external (no
      # vault, no other mount) -- it gets a tmpfiles `d` rule (so it's
      # guaranteed to exist before the service ever tries to start) and
      # WorkingDirectory=dataDir. For anything gated by external state
      # (a Casket vault, say), leave this false: systemd applies
      # WorkingDirectory= to EVERY exec step including ExecStartPre, so
      # if dataDir doesn't exist yet, not even a prestart that was meant
      # to check/create it can run -- found this the hard way (Stash and
      # Ollama both hit exit code 200/CHDIR on a real rebuild). Services
      # that need this false must do their own existence check in
      # preStart (absolute paths, no CWD needed) and their own `cd` in
      # execStart once that's confirmed, instead of relying on this.
    , ensureDataDir ? false
      # Paths that must already be mountpoints before this service (or any
      # of its preStart) runs -- generic, knows nothing about Casket,
      # vaults, or ".img" specifically, and not limited to one: a service
      # depending on two vaults, or a vault plus an unrelated external
      # drive, just lists both. A service that needs none leaves this `[
      # ]` and gets no check at all. Checked first, ahead of preStart,
      # since the whole point is catching "not mounted" before anything
      # that assumes it is gets a chance to run.
    , requireMounts ? [ ]
      # Path to a root-owned KEY=VALUE file systemd reads directly at
      # start -- Nix only ever knows this path, never the secret values
      # themselves (never embedded in the store). "-" prefix makes it
      # optional: a service with no real secrets yet just never has the
      # file, no error. Written by `secrets self-hosted <name>`, not by
      # Nix -- same hashedPasswordFile-style split as the login password.
    , environmentFile ? null
    }:
    let
      mountChecks = map
        (path: ''
          mountpoint -q "${path}" || {
            echo "self-hosted-${name}: ${path} is not mounted" >&2
            exit 1
          }
        '')
        requireMounts;
    in
    {
      systemd.services."self-hosted-${name}" = {
        description = "self-hosted: ${name}";
        # autoStart = false means it still exists and can be started by
        # hand (`systemctl start self-hosted-<name>`), it just isn't
        # pulled in on boot/rebuild.
        wantedBy = lib.optionals autoStart [ "multi-user.target" ];
        path = packages;
        inherit environment;
        serviceConfig = {
          User = user;
          ExecStartPre = lib.imap0
            (i: cmd: "${pkgs.writeShellScript "self-hosted-${name}-prestart-${toString i}" cmd}")
            (mountChecks ++ preStart);
          ExecStart = execStart;
          Restart = "on-failure";
        } // lib.optionalAttrs (dataDir != null && ensureDataDir) {
          WorkingDirectory = dataDir;
        } // lib.optionalAttrs (environmentFile != null) {
          EnvironmentFile = "-${environmentFile}";
        };
      };

      systemd.tmpfiles.rules =
        lib.optionals (dataDir != null && ensureDataDir)
          [ "d ${dataDir} 0755 ${user} - -" ]
        ++ lib.optionals (storage != [ ])
          (map (s: "L+ ${dataDir}/${s.src} - - - - ${s.dest}") storage);
    };

  # A pure, reproducible sandbox for services whose dependencies need a
  # real FHS layout (compiled Python wheels expecting /lib, /usr/lib --
  # nothing about this derivation itself is impure, it's a symlink+
  # bind-mount merge of targetPkgs, same as pkgs.symlinkJoin, not copies).
  mkFHSVenv = { name, targetPkgs }:
    pkgs.buildFHSEnv { name = "self-hosted-${name}-fhs"; inherit targetPkgs; };

  # The one deliberately-impure step in the whole system, confined to
  # exactly this: create a venv, install from a hash-locked requirements
  # file inside the FHS sandbox above. Never referenced by execStart as a
  # derivation -- only venvDir (a plain path) is, so a broken/stale lock
  # can only ever fail this action, never `nixos-rebuild switch` for the
  # rest of the system.
  mkVenvInstallScript = { fhsEnv, venvDir, requirementsLock, extraSteps ? "" }: ''
    ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
      set -euo pipefail
      rm -rf "${venvDir}"
      python3 -m venv "${venvDir}"
      "${venvDir}/bin/pip" install --require-hashes -r "${requirementsLock}"
      ${extraSteps}
    ''}
  '';

  # The `@uninstall` action every service gets. Two tiers, both
  # idempotent (rm -rf on an already-missing path is a no-op) so they can
  # run in either order or independently:
  #
  # Tier 1 (includeData = false, "@uninstall"): venvDir plus everything
  # directly under dataDir *except* what a storage entry's `src` covers
  # -- i.e. exactly the stuff @install/@sync put there. Recoverable: the
  # pins/lockfile are untouched, @install and/or @sync bring it all back.
  # Never touches the Nix store -- reclaiming unused store paths is
  # garbage collection's job (`pacnix orphaned`), not this.
  #
  # Tier 2 (includeData = true, "@uninstall:data"): tier 1, plus what
  # each storage entry's `dest` actually points at -- the real data this
  # service was fronting. Not recoverable. Always includes tier 1 too, so
  # it's a complete teardown regardless of whether tier 1 already ran.
  mkUninstallScript = { dataDir, storage ? [ ], venvDir ? null, includeData ? false }:
    let
      storageSrcs = lib.concatStringsSep " " (map (s: s.src) storage);
    in
    ''
      set -euo pipefail
      ${lib.optionalString (venvDir != null) ''rm -rf "${venvDir}"''}
      storage_srcs="${storageSrcs}"
      if [ -d "${dataDir}" ]; then
        for entry in "${dataDir}"/*; do
          [ -e "$entry" ] || continue
          name="$(basename "$entry")"
          skip=0
          for s in $storage_srcs; do
            [ "$s" = "$name" ] && { skip=1; break; }
          done
          [ "$skip" = 1 ] || rm -rf "$entry"
        done
      fi
    ''
    + lib.optionalString includeData (lib.concatMapStringsSep "\n"
      (s: ''
        rm -rf "${s.dest}"
        rm -f "${dataDir}/${s.src}"
      '')
      storage);

  # Shared by every service with a hash-locked venv (OpenWebUI, ComfyUI):
  # re-run pip-compile against the existing requirementsIn, diff the
  # result against the checked-in requirementsLock. Two modes:
  #
  # apply = false (the "@update:deps"-style action): print/diff only,
  # never overwrites the real lock -- leaves the new one at
  # "<requirementsLockPath>.new" if it differs. Predictable, stable path
  # (not a mktemp dir that vanishes when the unit exits) so there's
  # always something to `mv` into place if you like what you see.
  #
  # apply = true (the "@update:deps:apply"-style action): same check,
  # but if it differs, moves the new lock straight into place instead of
  # just printing where it is.
  #
  # requirementsIn/requirementsLock (Nix paths) are only ever *read* here
  # (pip-compile's input, diff's baseline) -- fine as store copies.
  # requirementsLockPath is deliberately a plain string, the real
  # filesystem path in the actual Dotfiles checkout, not a Nix path --
  # ${requirementsLock} would resolve to a read-only /nix/store copy, and
  # writing there would be both wrong (not where you'd look for it) and
  # impossible (the store is read-only).
  mkDepsUpdateScript = { serviceName, requirementsIn, requirementsLock, requirementsLockPath, apply ? false }: ''
    set -euo pipefail
    new_lock="${requirementsLockPath}.new"
    pip-compile --generate-hashes --allow-unsafe --resolver=backtracking \
      --output-file="$new_lock" "${requirementsIn}" >/dev/null

    if diff -q "${requirementsLock}" "$new_lock" >/dev/null 2>&1; then
      echo "self-hosted-${serviceName}: requirements.lock is already up to date"
      rm -f "$new_lock"
      exit 0
    fi

    echo "self-hosted-${serviceName}: newer requirements available -- package/version diff:"
    diff <(grep -E '^[a-zA-Z0-9_.-]+==' "${requirementsLock}") \
         <(grep -E '^[a-zA-Z0-9_.-]+==' "$new_lock") || true
  ''
  + (if apply then ''
    mv "$new_lock" "${requirementsLockPath}"
    echo ""
    echo "self-hosted-${serviceName}: applied -- requirements.lock updated. Rebuild + restart + @install to actually use it."
  '' else ''
    echo ""
    echo "Full new lock at: $new_lock"
    echo "Apply with: mv \"$new_lock\" \"${requirementsLockPath}\", or just run the :apply variant of this action."
  '');

  # Manual-only maintenance actions (sync, cleanup, whatever a service
  # needs) as ONE systemd template unit per service instead of a separate
  # top-level unit name per action -- `systemctl start
  # self-hosted-<name>@<action>` groups under the same unit family as the
  # live self-hosted-<name>.service rather than scattering independent
  # service names. Never WantedBy=, never a dependency of the live service
  # or of system activation -- a rebuild only ever changes what's
  # *declared*, never triggers a fetch.
  mkActionService =
    { name
    , actions # attrsOf str -- action name -> script body
    , user
    , packages ? [ ]
    , environment ? { }
    , environmentFile ? null # same as mkSelfHostedService's -- e.g. a model-sync action needing HF_TOKEN
    }:
    let
      dispatch = pkgs.writeShellScript "self-hosted-${name}-dispatch" ''
        set -euo pipefail
        case "$1" in
        ${lib.concatStrings (lib.mapAttrsToList (action: script: ''
          ${action})
            exec ${pkgs.writeShellScript "self-hosted-${name}-${action}" script}
            ;;
        '') actions)}
          *) echo "self-hosted-${name}: unknown action '$1'" >&2; exit 1 ;;
        esac
      '';
    in
    {
      systemd.services."self-hosted-${name}@" = {
        description = "self-hosted: ${name} (%i)";
        path = packages;
        inherit environment;
        serviceConfig = {
          User = user;
          Type = "oneshot";
          ExecStart = "${dispatch} %i";
        } // lib.optionalAttrs (environmentFile != null) {
          EnvironmentFile = "-${environmentFile}";
        };
      };
    };
}
