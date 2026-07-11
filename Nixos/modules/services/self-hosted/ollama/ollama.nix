{ config, lib, pkgs, ... }:

# Wiring only -- the package build is ./package.nix, the reconciliation
# behavior is ./sync.nix, the generic systemd plumbing is
# ../self-hosted.nix. This file's only job is tying those together with
# this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.ollama;

  package = import ./package.nix { inherit pkgs; } { inherit (cfg) version hash; };

  syncScript = import ./sync.nix { inherit package; };

  # cfg.environment is plain passthrough (see default.nix) -- the only
  # thing added here is OLLAMA_MODELS, and only because it has to agree
  # with dataDir (also used for storage below), not because it needs its
  # own typed option. `//` means this always wins over anything the same
  # key in cfg.environment might set, so dataDir stays the one source of
  # truth for where models live.
  environment = cfg.environment // {
    OLLAMA_MODELS = "${cfg.dataDir}/models";
  };

in

{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "ollama";
      user = config.vars.username;
      execStart = "${package}/bin/ollama serve";
      inherit (cfg) dataDir storage autoStart;
      inherit environment;
    })
    (selfHosted.mkActionService {
      name = "ollama";
      user = config.vars.username;
      actions.sync = syncScript;
      environment = environment // {
        OLLAMA_MODELS_DECLARED = builtins.concatStringsSep " " cfg.models;
      };
    })
  ]);
}
