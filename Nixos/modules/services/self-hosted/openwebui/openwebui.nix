{ config, lib, pkgs, ... }:

# Wiring only -- the FHS sandbox is ./fhs.nix, the generic systemd/venv
# plumbing is ../self-hosted.nix. This file's only job is tying those
# together with this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.services.selfHosted.openwebui;

  fhsEnv = import ./lib/fhs.nix { inherit pkgs; };

  # dataDir/storage split same as Stash: dataDir is plain, the one real
  # data location is the (single) storage entry, pointing into the
  # SelfHosted vault -- confirmed the correct one, not the "Vaults" vault
  # the old (stale) obsidian-unlock.sh hook referenced.
  liveDataDir = "${cfg.dataDir}/${(builtins.head cfg.storage).src}";

  # Generated once if missing, persisted alongside the actual data so it
  # survives a venv reinstall -- same pattern as the old install.sh, just
  # moved into preStart so it's self-healing on every start rather than
  # only handled at install time.
  secretKeyFile = "${liveDataDir}/.webui_secret_key";

  venvEnsureScript = selfHosted.mkVenvEnsureScript {
    inherit fhsEnv;
    venvDir = cfg.venvDir;
    # Lives under Dotfiles/Python/locks/ rather than next to this file --
    # a 5700+ line generated pip lockfile doesn't belong sitting alongside
    # the hand-written .nix files. Still has to stay inside Dotfiles/
    # somewhere (Nix's pure-eval mode refuses to read anything outside
    # the flake's own tree -- confirmed empirically early in this
    # project, not an assumption). Same convention for ComfyUI's eventual
    # (much bigger) lockfile.
    requirementsLock = ../../../../../Python/locks/self-hosted/openwebui/requirements.lock;
  };

  # Deliberately a plain string, not a Nix path -- that resolves to a
  # read-only /nix/store copy, this is the real, writable location in
  # the actual checkout, needed so the ".new" sibling (or the :apply
  # variant's direct write) lands somewhere real.
  openwebuiRequirementsLockPath = "${config.vars.identity.homeDirectory}/Dotfiles/Python/locks/self-hosted/openwebui/requirements.lock";
  updateScript = import ./lib/update.nix {
    inherit selfHosted;
    requirementsIn = ../../../../../Python/locks/self-hosted/openwebui/requirements.in;
    requirementsLock = ../../../../../Python/locks/self-hosted/openwebui/requirements.lock;
    requirementsLockPath = openwebuiRequirementsLockPath;
  };
  updateApplyScript = import ./lib/update.nix {
    inherit selfHosted;
    requirementsIn = ../../../../../Python/locks/self-hosted/openwebui/requirements.in;
    requirementsLock = ../../../../../Python/locks/self-hosted/openwebui/requirements.lock;
    requirementsLockPath = openwebuiRequirementsLockPath;
    apply = true;
  };

  # cfg.environment is plain passthrough (see default.nix) -- DATA_DIR is
  # added here because it has to agree with liveDataDir, not because it
  # needs its own typed option.
  environment = cfg.environment // {
    DATA_DIR = liveDataDir;
  };

in

{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "openwebui";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      homeDirectory = config.vars.identity.homeDirectory;
      # Runs inside the FHS sandbox too, not just the install action --
      # the compiled wheels pip installs (pillow, lxml) need real
      # /lib,/usr/lib every time Python imports them, not just once at
      # install time.
      execStart = "${pkgs.writeShellScript "self-hosted-openwebui-start" ''
        export WEBUI_SECRET_KEY="$(cat "${secretKeyFile}")"
        exec ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
          exec "${cfg.venvDir}/bin/open-webui" serve --host ${cfg.host} --port ${toString cfg.port}
        ''}
      ''}";
      # venv ensure runs here now, every start, not as a separate manual
      # @install -- mkVenvEnsureScript skips the real install unless
      # requirementsLock actually changed since the last successful run.
      preStart = [
        "mkdir -p ${liveDataDir}"
        ''
          if [ ! -f "${secretKeyFile}" ]; then
            head -c 32 /dev/urandom | base64 | tr -d '\n' > "${secretKeyFile}"
            chmod 600 "${secretKeyFile}"
          fi
        ''
        venvEnsureScript
      ];
      ensureDataDir = true;
      inherit (cfg) dataDir storage autoStart requireMounts teardownPaths;
      venvDir = cfg.venvDir;
      inherit environment;
    })
    (selfHosted.mkActionService {
      name = "openwebui";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      # pip-tools for @update's pip-compile -- doesn't need the FHS
      # sandbox, compiling/resolving is pure network+pip, only the actual
      # venv install (now in preStart above) needs the real
      # /lib,/usr/lib layout.
      packages = [ pkgs.python312Packages.pip-tools ];
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
      };
    })
  ];
}
