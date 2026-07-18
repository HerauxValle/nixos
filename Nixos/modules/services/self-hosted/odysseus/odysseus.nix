{ config, lib, pkgs, ... }:

# Wiring only -- the FHS sandbox is ./lib/fhs.nix, the generic
# systemd/venv plumbing is ../self-hosted.nix. This file's only job is
# tying those together with this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.services.selfHosted.odysseus;

  fhsEnv = import ./lib/fhs.nix { inherit pkgs; };

  venvEnsureScript = selfHosted.mkVenvEnsureScript {
    inherit fhsEnv;
    venvDir = cfg.venvDir;
    requirementsLock = ../../../../../Python/locks/self-hosted/odysseus/requirements.lock;
  };

  # Pinned-but-writable, same shape as SearXNG's own srcEnsureScript --
  # idempotent: a clone already sitting at coreRev is a no-op, only ever
  # fetches when coreRev has actually changed underneath it (e.g. after
  # an @update:core:apply + rebuild).
  srcEnsureScript = ''
    if [ -d "${cfg.srcDir}/.git" ]; then
      current_rev="$(git -C "${cfg.srcDir}" rev-parse HEAD)"
      if [ "$current_rev" != "${cfg.coreRev}" ]; then
        git -C "${cfg.srcDir}" fetch origin
        git -C "${cfg.srcDir}" checkout "${cfg.coreRev}"
      fi
    else
      git clone https://github.com/pewdiepie-archdaemon/odysseus.git "${cfg.srcDir}"
      git -C "${cfg.srcDir}" checkout "${cfg.coreRev}"
    fi
  '';

  # Real vault-backed data (data/, logs/, .env -- see default.nix's own
  # storage comment) symlinked directly into srcDir, not a separate
  # dataDir -- Odysseus's own application code (setup.py, core/database.py,
  # load_dotenv()) computes these as plain subdirectories/files relative
  # to wherever the running script lives, with no env-var override the
  # way SearXNG's SEARXNG_SETTINGS_PATH provides. Same rm-rf-then-symlink
  # idiom as SearXNG's own themeLinkScript -- a fresh git clone can ship
  # its own placeholder paths (or none at all yet), and a bare `ln -sfn`
  # can't force-replace a real directory, only an existing symlink.
  dataLinkScript = lib.concatMapStringsSep "\n"
    (s: ''
      rm -rf "${cfg.srcDir}/${s.src}"
      ln -sfn "${s.dest}" "${cfg.srcDir}/${s.src}"
    '')
    cfg.storage;

  # Idempotent per its own docstring ("Safe to re-run (skips what
  # already exists)") -- creates data/{uploads,personal_docs,...}/logs
  # if missing (a no-op here, they already exist for real inside the
  # vault-backed data/ this dataLinkScript just symlinked in) and an
  # admin account only if data/auth.json doesn't already exist (it does,
  # for real -- confirmed by inspecting the vault directly, this is a
  # genuine no-op on this machine, not a fresh bootstrap the way
  # Immich's turned out to be). ODYSSEUS_SKIP_ADMIN_PROMPT is set
  # defensively -- setup.py already detects a non-interactive stdin
  # (never a real TTY under systemd) and skips prompting on its own, but
  # being explicit doesn't rely on that detection alone.
  #
  # Runs inside the FHS sandbox -- found the hard way on a real run:
  # venvDir/bin/python is a symlink chain ending at /usr/bin/python3
  # (venv's own behavior, records whatever `python3` resolved to at
  # creation time, which inside the sandbox is a bind-mounted
  # /usr/bin/python3) -- that target only exists from inside the FHS
  # sandbox's own rootfs, not from a plain preStart shell. execStart
  # already runs inside the sandbox for the identical reason; this needs
  # to as well, not just the venv-install step.
  setupScript = "${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
    cd "${cfg.srcDir}"
    ODYSSEUS_SKIP_ADMIN_PROMPT=1 "${cfg.venvDir}/bin/python" setup.py
  ''}";

  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  odysseusConfigFile = "${config.vars.identity.homeDirectory}/Dotfiles/Nixos/config/self-hosted/odysseus.nix";
  odysseusRequirementsLockPath = "${config.vars.identity.homeDirectory}/Dotfiles/Python/locks/self-hosted/odysseus/requirements.lock";
  updateActions = import ./lib/update.nix {
    inherit lib selfHosted cfg;
    requirementsIn = ../../../../../Python/locks/self-hosted/odysseus/requirements.in;
    requirementsLock = ../../../../../Python/locks/self-hosted/odysseus/requirements.lock;
    requirementsLockPath = odysseusRequirementsLockPath;
    configFile = odysseusConfigFile;
  };

in

{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "odysseus";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      homeDirectory = config.vars.identity.homeDirectory;
      # Runs inside the FHS sandbox too, not just preStart -- bcrypt/
      # cryptography/lxml/pillow/onnxruntime need the real /lib,/usr/lib
      # on every import, not just once at install. cd srcDir first,
      # matching upstream's own odysseus-ui.service template exactly
      # (WorkingDirectory=.../odysseus-ui, ExecStart=.../uvicorn app:app
      # --port ... --host ...) -- uvicorn resolves `app:app` relative to
      # cwd, no .pth trick needed (unlike SearXNG's `import searx`).
      execStart = "${pkgs.writeShellScript "self-hosted-odysseus-start" ''
        cd "${cfg.srcDir}"
        exec ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
          exec "${cfg.venvDir}/bin/uvicorn" app:app --host ${cfg.host} --port ${toString cfg.port}
        ''}
      ''}";
      preStart = [
        ''mkdir -p "$(dirname "${cfg.venvDir}")" "$(dirname "${cfg.srcDir}")"''
        srcEnsureScript
        venvEnsureScript
        dataLinkScript
        setupScript
      ];
      # git for srcEnsureScript, same reasoning fhs.nix's own git is
      # needed for (that one's inside the sandbox, this one's the plain
      # preStart shell outside it).
      packages = [ pkgs.git ];
      # Deliberately NOT passing storage/dataDir here -- unlike every
      # other storage-having service, cfg.storage is consumed entirely
      # by dataLinkScript above (symlinked into srcDir, not a dataDir
      # this framework's own dataDir-based L+ tmpfiles mechanism knows
      # about). Passing storage without a real dataDir would crash that
      # mechanism outright (it interpolates "${dataDir}/${s.src}"
      # unconditionally whenever storage is non-empty, and dataDir is
      # null here) -- confirmed by reading mk-self-hosted-service.nix
      # directly before writing this, not found the hard way.
      inherit (cfg) autoStart requireMounts environment;
      venvDir = cfg.venvDir;
    })
    (selfHosted.mkActionService {
      name = "odysseus";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      # git for update:core's ls-remote, curl+jq/nix for
      # mkDepsUpdateScript's pip-compile-diff -- only @update* needs
      # these.
      packages = [ pkgs.git pkgs.curl pkgs.jq pkgs.nix pkgs.python314Packages.pip-tools ];
      actions = updateActions;
    })
  ];
}
