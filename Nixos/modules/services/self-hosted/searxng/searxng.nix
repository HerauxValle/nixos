{ config, lib, pkgs, ... }:

# Wiring only -- the FHS sandbox is ./lib/fhs.nix, the generic
# systemd/venv plumbing is ../self-hosted.nix. This file's only job is
# tying those together with this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.services.selfHosted.searxng;

  fhsEnv = import ./lib/fhs.nix { inherit pkgs; };

  # The one real data location -- a single-file symlink, not a
  # directory. dataDir/settings.yml -> the real, hand-customized
  # settings.yml in the vault. Nix never reads or writes its contents.
  settingsPath = "${cfg.dataDir}/${(builtins.head cfg.storage).src}";

  # cfg.environment is plain passthrough (see default.nix) -- SEARXNG_SECRET
  # is added here because it's structurally consumed (SearXNG's own
  # settings_defaults.py reads it as a real override for
  # server.secret_key), not because it needs its own separate mechanism.
  # host/port work the same way but are optional (null = omit the env var
  # entirely, settings.yml's own values apply) -- unlike secret, which is
  # always required and always set.
  environment = cfg.environment // {
    SEARXNG_SECRET = cfg.secret;
    SEARXNG_SETTINGS_PATH = settingsPath;
  } // lib.optionalAttrs (cfg.host != null) {
    SEARXNG_BIND_ADDRESS = cfg.host;
  } // lib.optionalAttrs (cfg.port != null) {
    SEARXNG_PORT = toString cfg.port;
  };

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

  # searx/webutils.py's get_result_templates() walks searx/templates/
  # with os.walk(templates_path) -- no followlinks=True. Since
  # themeLinkScript below replaces searx/templates/<name> with a symlink
  # into the Nix store, os.walk refuses to descend into it, so the
  # discovered result_templates set stays empty and every themed
  # get_result_template() lookup (webapp.py) falls through to the
  # un-themed "result_templates/<x>.html" path, which doesn't exist --
  # crashing every /search with jinja2.exceptions.TemplateNotFound.
  # Confirmed by reading webutils.py directly. sed only matches the
  # pristine checkout, so re-running this after coreRev's git checkout is
  # a no-op once already patched -- idempotent like srcEnsureScript.
  webutilsFollowlinksPatch = ''
    sed -i "s/os\.walk(templates_path):/os.walk(templates_path, followlinks=True):/" "${cfg.srcDir}/searx/webutils.py"
  '';

  # Same mechanism as the old links.sh: every declared theme gets
  # symlinked into the live checkout's searx/templates/<name> and
  # searx/static/themes/<name>. rm -rf the destination first, every
  # time, before symlinking -- ln -sfn alone can't force-replace an
  # existing *real* directory (only an existing symlink), and "simple"
  # collides with exactly that: SearXNG's own git source already ships a
  # stock searx/templates/simple/ directory, which a bare `ln -sfn` fails
  # against silently. Confirmed on a real run: the custom simple theme
  # (genuinely hand-edited results.html/preferences.html, not just a
  # duplicate of stock) was silently not taking effect until this rm -rf
  # was added. Safe to rm -rf unconditionally -- srcDir is a disposable,
  # regenerable checkout, never real user data.
  themeLinkScript = ''
    mkdir -p "${cfg.srcDir}/searx/templates" "${cfg.srcDir}/searx/static/themes"
  '' + lib.concatMapStringsSep "\n"
    (theme: ''
      if [ -d "${theme.path}/templates" ]; then
        rm -rf "${cfg.srcDir}/searx/templates/${theme.name}"
        ln -sfn "${theme.path}/templates" "${cfg.srcDir}/searx/templates/${theme.name}"
      fi
      if [ -d "${theme.path}/static" ]; then
        rm -rf "${cfg.srcDir}/searx/static/themes/${theme.name}"
        ln -sfn "${theme.path}/static" "${cfg.srcDir}/searx/static/themes/${theme.name}"
      fi
    '')
    cfg.themes;

  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  searxngConfigFile = "${config.vars.identity.homeDirectory}/Dotfiles/Nixos/config/self-hosted/searxng.nix";
  searxngRequirementsLockPath = "${config.vars.identity.homeDirectory}/Dotfiles/Python/locks/self-hosted/searxng/requirements.lock";
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
      user = config.vars.identity.username;
      homeDirectory = config.vars.identity.homeDirectory;
      # Runs inside the FHS sandbox too, not just preStart -- lxml needs
      # the real /lib,/usr/lib on every import, not just once at install.
      execStart = "${pkgs.writeShellScript "self-hosted-searxng-start" ''
        cd "${cfg.srcDir}"
        exec ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
          exec "${cfg.venvDir}/bin/python" searx/webapp.py
        ''}
      ''}";
      preStart = [
        ''mkdir -p "$(dirname "${cfg.venvDir}")" "$(dirname "${cfg.srcDir}")"''
        srcEnsureScript
        webutilsFollowlinksPatch
        venvEnsureScript
        themeLinkScript
      ];
      # git for srcEnsureScript, same reasoning fhs.nix's own git is
      # needed for (that one's inside the sandbox, this one's the plain
      # preStart shell outside it).
      packages = [ pkgs.git ];
      ensureDataDir = true; # dataDir itself is plain, safe to auto-create
      inherit (cfg) dataDir storage autoStart requireMounts teardownPaths;
      inherit environment;
      venvDir = cfg.venvDir;
    })
    (selfHosted.mkActionService {
      name = "searxng";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      # git for update:core's ls-remote, curl+jq/nix for
      # mkDepsUpdateScript's pip-compile-diff -- only @update* needs
      # these.
      packages = [ pkgs.git pkgs.curl pkgs.jq pkgs.nix pkgs.python312Packages.pip-tools ];
      actions = updateActions;
    })
  ];
}
