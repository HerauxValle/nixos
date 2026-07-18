{ config, lib, pkgs, ... }:

# Wiring only -- the package build is ./package.nix, the reconciliation
# behavior is ./sync.nix, the generic systemd plumbing is
# ../self-hosted.nix. This file's only job is tying those together with
# this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.services.selfHosted.ollama;

  package = import ./lib/package.nix { inherit pkgs; } { inherit (cfg) version hash; };

  syncScript = import ./lib/sync.nix { inherit package; };
  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  ollamaConfigFile = "${config.vars.identity.homeDirectory}/Dotfiles/Nixos/config/self-hosted/ollama.nix";
  updateScript = import ./lib/update.nix { inherit cfg; configFile = ollamaConfigFile; };
  updateApplyScript = import ./lib/update.nix { inherit cfg; configFile = ollamaConfigFile; apply = true; };

  # cfg.environment is plain passthrough (see default.nix) -- OLLAMA_MODELS
  # is added here because it has to agree with dataDir (also used for
  # storage below), not because it needs its own typed option. `//` means
  # this always wins over anything the same key in cfg.environment might
  # set, so dataDir stays the one source of truth for where models live.
  #
  # OLLAMA_HOST works the same way, but only if cfg.host/cfg.port are
  # actually set -- host/port are optional typed overrides (default
  # null), not the primary mechanism (that's still environment.OLLAMA_HOST
  # directly, same as before this option existed). Whichever half you
  # didn't set falls back to Ollama's own conventional default
  # (0.0.0.0/11434), not whatever might already be in
  # environment.OLLAMA_HOST -- setting either one means you're overriding
  # the whole value, not patching half of an existing string.
  hostPortOverride = lib.optionalAttrs (cfg.host != null || cfg.port != null) {
    OLLAMA_HOST = "${if cfg.host != null then cfg.host else "0.0.0.0"}:${if cfg.port != null then toString cfg.port else "11434"}";
  };

  environment = cfg.environment // {
    OLLAMA_MODELS = "${cfg.dataDir}/models";
  } // hostPortOverride;

in

{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "ollama";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      homeDirectory = config.vars.identity.homeDirectory;
      execStart = "${package}/bin/ollama serve";
      # Model reconciliation runs here now, every start, not as a
      # separate manual @sync -- postStart because it goes through
      # ollama's own HTTP API, which needs the server actually up first
      # (see sync.nix's wait-until-ready loop).
      postStart = [ syncScript ];
      # gawk -- sync.nix parses `ollama list` output with awk. Confirmed
      # missing on a real run ("awk: command not found"), unlike
      # grep/tail/seq which are already on the base NixOS system PATH.
      # A failing ExecStartPost fails the whole unit, so this alone was
      # enough to start-limit-hit the service.
      packages = [ pkgs.gawk ];
      inherit (cfg) dataDir storage autoStart teardownPaths;
      ensureDataDir = true; # not gated by any external mount -- safe to auto-create
      environment = environment // {
        OLLAMA_MODELS_DECLARED = builtins.concatStringsSep " " cfg.models;
      };
    })
    (selfHosted.mkActionService {
      name = "ollama";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      # curl+jq for the GitHub releases API, nix for
      # nix-prefetch-url/nix hash convert -- only @update actually needs
      # these, but packages is shared across the whole action template.
      packages = [ pkgs.curl pkgs.jq pkgs.nix ];
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
      };
    })
  ];
}
