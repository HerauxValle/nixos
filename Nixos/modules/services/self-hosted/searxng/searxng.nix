{ config, lib, pkgs, ... }:

# Wiring only -- the FHS sandbox is ./lib/fhs.nix, the generic
# systemd/venv plumbing is ../self-hosted.nix. This file's only job is
# tying those together with this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.searxng;

  fhsEnv = import ./lib/fhs.nix { inherit pkgs; };

  # The one real data location -- a single-file symlink, not a
  # directory. dataDir/settings.yml -> the real, hand-customized
  # settings.yml in the vault. Nix never reads or writes its contents.
  settingsPath = "${cfg.dataDir}/${(builtins.head cfg.storage).src}";

  secretKeyFile = "${cfg.dataDir}/.searxng_secret_key";

  # searxng has no pip package (confirmed in the ported toolchain.sh's
  # own comment) -- this writes a .pth file into the venv's
  # site-packages pointing at srcDir, exactly like the old install.sh's
  # `echo "$SEARXNG_PATH" > .../searxng.pth`, so `import searx` resolves
  # to the checked-out source instead of needing a real `pip install .`.
  # Runs inside the FHS sandbox (mkVenvInstallScript's extraSteps),
  # right after the hash-locked requirements finish installing.
  pthExtraStep = ''
    echo "${cfg.srcDir}" > "${cfg.venvDir}/lib/python3.12/site-packages/searxng.pth"
  '';

  venvEnsureScript = selfHosted.mkVenvEnsureScript {
    inherit fhsEnv;
    venvDir = cfg.venvDir;
    requirementsLock = ../../../../../Python/locks/self-hosted/searxng/requirements.lock;
    extraSteps = pthExtraStep;
  };

  # Pinned-but-writable, unlike ComfyUI's core (see default.nix's top
  # comment for why) -- a plain git clone, checked out to coreRev every
  # start. Idempotent: a clone already sitting at coreRev is a no-op:
  # this only ever fetches when coreRev has actually changed underneath
  # it (e.g. after an @update:core:apply + rebuild).
  srcEnsureScript = ''
    if [ -d "${cfg.srcDir}/.git" ]; then
      current_rev="$(git -C "${cfg.srcDir}" rev-parse HEAD)"
      if [ "$current_rev" != "${cfg.coreRev}" ]; then
        git -C "${cfg.srcDir}" fetch origin
        git -C "${cfg.srcDir}" checkout "${cfg.coreRev}"
      fi
    else
      git clone https://github.com/searxng/searxng.git "${cfg.srcDir}"
      git -C "${cfg.srcDir}" checkout "${cfg.coreRev}"
    fi
  '';

  # Same mechanism as the old links.sh: every declared theme gets
  # symlinked into the live checkout's searx/templates/<name> and
  # searx/static/themes/<name>. -sfn (not just -sf) so re-running this
  # against an already-linked theme replaces the symlink itself rather
  # than risking "target is a directory" if the destination somehow
  # isn't a symlink yet.
  themeLinkScript = ''
    mkdir -p "${cfg.srcDir}/searx/templates" "${cfg.srcDir}/searx/static/themes"
  '' + lib.concatMapStringsSep "\n"
    (theme: ''
      [ -d "${theme.path}/templates" ] && ln -sfn "${theme.path}/templates" "${cfg.srcDir}/searx/templates/${theme.name}"
      [ -d "${theme.path}/static" ] && ln -sfn "${theme.path}/static" "${cfg.srcDir}/searx/static/themes/${theme.name}"
    '')
    cfg.themes;

  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  searxngConfigFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/searxng.nix";
  searxngRequirementsLockPath = "${config.vars.homeDirectory}/Dotfiles/Python/locks/self-hosted/searxng/requirements.lock";
  updateActions = import ./lib/update.nix {
    inherit lib selfHosted cfg;
    requirementsIn = ../../../../../Python/locks/self-hosted/searxng/requirements.in;
    requirementsLock = ../../../../../Python/locks/self-hosted/searxng/requirements.lock;
    requirementsLockPath = searxngRequirementsLockPath;
    configFile = searxngConfigFile;
  };

in

{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "searxng";
      enabled = cfg.enabled;
      user = config.vars.username;
      homeDirectory = config.vars.homeDirectory;
      # Runs inside the FHS sandbox too, not just preStart -- lxml needs
      # the real /lib,/usr/lib on every import, not just once at install.
      execStart = "${pkgs.writeShellScript "self-hosted-searxng-start" ''
        export SEARXNG_SECRET_KEY="$(cat "${secretKeyFile}")"
        export SEARXNG_SETTINGS_PATH="${settingsPath}"
        cd "${cfg.srcDir}"
        exec ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
          exec "${cfg.venvDir}/bin/python" searx/webapp.py
        ''}
      ''}";
      preStart = [
        ''mkdir -p "$(dirname "${cfg.venvDir}")" "$(dirname "${cfg.srcDir}")"''
        srcEnsureScript
        venvEnsureScript
        themeLinkScript
        ''
          if [ ! -f "${secretKeyFile}" ]; then
            head -c 32 /dev/urandom | base64 | tr -d '\n' > "${secretKeyFile}"
            chmod 600 "${secretKeyFile}"
          fi
        ''
      ];
      # git for srcEnsureScript, same reasoning fhs.nix's own git is
      # needed for (that one's inside the sandbox, this one's the plain
      # preStart shell outside it).
      packages = [ pkgs.git ];
      ensureDataDir = true; # dataDir itself is plain, safe to auto-create
      inherit (cfg) dataDir storage autoStart environment requireMounts teardownPaths;
      venvDir = cfg.venvDir;
    })
    (selfHosted.mkActionService {
      name = "searxng";
      enabled = cfg.enabled;
      user = config.vars.username;
      # git for update:core's ls-remote, curl+jq/nix for
      # mkDepsUpdateScript's pip-compile-diff -- only @update* needs
      # these.
      packages = [ pkgs.git pkgs.curl pkgs.jq pkgs.nix pkgs.python312Packages.pip-tools ];
      actions = updateActions;
    })
  ];
}
