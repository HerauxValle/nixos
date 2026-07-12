{ lib, pkgs, mkTeardownActivationScript }:

# The live process. Restart=on-failure replaces the old bash framework's
# nohup+PID-file+kill-loop entirely.
{ name
  # Default false, matching every service's own `enabled` schema
  # option -- inert-by-default is the safe choice, same reasoning as
  # `ensureDataDir`/`autoStart` above. true = the live service (below)
  # exists and runs. false = none of it exists, and
  # mkTeardownActivationScript fires instead (see its own comment) --
  # this one flag drives both halves of the lifecycle, so no caller
  # has to hand-wire lib.mkIf/lib.mkMerge around this function's
  # result itself.
, enabled ? false
, execStart
, user
, packages ? [ ]
, environment ? { }
, preStart ? [ ]
  # Runs after execStart's process has actually been spawned --
  # ExecStartPost, not ExecStartPre. For reconciliation that can only
  # happen through the live process itself (Ollama's model
  # pull/rm/list all go through its own HTTP API, which obviously
  # isn't up yet during preStart). Each entry should wait until
  # actually ready itself (poll, don't assume) -- ExecStartPost fires
  # right after fork/exec, not once the process is confirmed serving.
, postStart ? [ ]
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
  # Needed only to compute ancestor-directory ownership fixes below
  # -- see the tmpfiles.rules comment. Skipped (no ancestor fixes)
  # if not given, matching this parameter's previous absence.
, homeDirectory ? null
  # Passed straight through to mkTeardownActivationScript -- see its
  # own comment for what these actually control. Not used at all
  # unless enabled = false.
, teardownPaths ? [ ]
, venvDir ? null
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

  # dataDir's own `d`/`z` pair only fixes dataDir itself -- if any
  # directory *between* homeDirectory and dataDir already exists
  # root-owned (e.g. ~/Applications, an auto-created, unmanaged
  # parent from some earlier root-run activation), systemd-tmpfiles
  # refuses to even walk through it to reach dataDir: "Detected
  # unsafe path transition ... during canonicalization" -- a real
  # safety check, not a bug, but it means dataDir's own ownership
  # fix silently no-ops if any ancestor is wrong. Found this the
  # hard way (ComfyUI's custom_nodes mkdir kept failing with
  # Permission denied even after adding dataDir's own `z` rule --
  # ~/Applications itself, one level up, was the actual culprit).
  # Fix: emit the same d+z pair for every ancestor directory between
  # homeDirectory (always safe -- it's the user's own home) and
  # dataDir, so the whole chain is guaranteed walkable.
  ancestorDirs =
    if dataDir == null || homeDirectory == null then [ ] else
    let
      baseParts = lib.splitString "/" homeDirectory;
      fullParts = lib.splitString "/" dataDir;
      relParts = lib.sublist
        (builtins.length baseParts)
        (builtins.length fullParts - builtins.length baseParts - 1)
        fullParts;
    in
    lib.genList
      (i: homeDirectory + "/" + lib.concatStringsSep "/" (lib.sublist 0 (i + 1) relParts))
      (builtins.length relParts);
in
lib.mkMerge [
  (lib.mkIf enabled {
    systemd.services."self-hosted-${name}" = {
      description = "self-hosted: ${name}";
      # autoStart = false means it still exists and can be started by
      # hand (`systemctl start self-hosted-<name>`), it just isn't
      # pulled in on boot/rebuild.
      wantedBy = lib.optionals autoStart [ "multi-user.target" ];
      # util-linux (mountpoint) only when requireMounts actually needs
      # it -- found via a real failure: "mountpoint: command not
      # found" on ComfyUI's live-service mount check. Not on a bare
      # systemd service's PATH by default, unlike an interactive
      # shell where it's already there. Callers never have to
      # remember this themselves.
      path = packages ++ lib.optionals (requireMounts != [ ]) [ pkgs.util-linux ];
      inherit environment;
      serviceConfig = {
        User = user;
        ExecStartPre = lib.imap0
          (i: cmd: "${pkgs.writeShellScript "self-hosted-${name}-prestart-${toString i}" cmd}")
          (mountChecks ++ preStart);
        ExecStart = execStart;
        ExecStartPost = lib.imap0
          (i: cmd: "${pkgs.writeShellScript "self-hosted-${name}-poststart-${toString i}" cmd}")
          postStart;
        Restart = "on-failure";
      } // lib.optionalAttrs (dataDir != null && ensureDataDir) {
        WorkingDirectory = dataDir;
      } // lib.optionalAttrs (environmentFile != null) {
        EnvironmentFile = "-${environmentFile}";
      };
    };

    systemd.tmpfiles.rules =
      lib.optionals (dataDir != null && ensureDataDir)
        [
          "d ${dataDir} 0755 ${user} - -"
          # `d` only sets ownership at creation time -- if dataDir
          # already exists (root:root, e.g. from some earlier
          # accidental root-owned creation), `d` alone silently leaves
          # it that way, and the service user then can't write inside
          # it (found this the hard way: ComfyUI's custom_nodes mkdir
          # failing with Permission denied, dataDir already existing
          # as root:root). `z` (non-recursive -- only this path
          # itself, not its contents) re-asserts ownership on every
          # activation regardless of whether `d` just created it or
          # it already existed.
          "z ${dataDir} 0755 ${user} - -"
        ]
      ++ (lib.concatMap
        (dir: [ "d ${dir} 0755 ${user} - -" "z ${dir} 0755 ${user} - -" ])
        ancestorDirs)
      ++ lib.optionals (storage != [ ])
        (map (s: "L+ ${dataDir}/${s.src} - - - - ${s.dest}") storage);
  })
  (mkTeardownActivationScript { inherit name enabled dataDir storage teardownPaths venvDir; })
]
