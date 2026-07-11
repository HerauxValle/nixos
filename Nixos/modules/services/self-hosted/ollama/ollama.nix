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
  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  ollamaConfigFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/ollama.nix";
  updateScript = import ./update.nix { inherit cfg; configFile = ollamaConfigFile; };
  updateApplyScript = import ./update.nix { inherit cfg; configFile = ollamaConfigFile; apply = true; };

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
      homeDirectory = config.vars.homeDirectory;
      execStart = "${package}/bin/ollama serve";
      inherit (cfg) dataDir storage autoStart;
      ensureDataDir = true; # not gated by any external mount -- safe to auto-create
      inherit environment;
    })
    (selfHosted.mkActionService {
      name = "ollama";
      user = config.vars.username;
      # curl+jq for the GitHub releases API, nix for
      # nix-prefetch-url/nix hash convert -- only @update actually needs
      # these, but packages is shared across the whole action template.
      packages = [ pkgs.curl pkgs.jq pkgs.nix ];
      actions = {
        # No venv, no download step -- the binary is a plain Nix store
        # path (package.nix), already there after any rebuild. This
        # exists purely so `@install` is a valid action on every
        # self-hosted service, not just the ones with a real install
        # step.
        install = ''echo "self-hosted-ollama: nothing to install -- the binary comes directly from the Nix store (package.nix), already available after rebuild."'';
        sync = syncScript;
        # Alias -- Ollama only ever had one syncable category, but every
        # other service's sync is addressable by target
        # (sync:models/sync:nodes), so this exists purely for that same
        # muscle memory to work here too.
        "sync:models" = syncScript;
        update = updateScript;
        "update:apply" = updateApplyScript;
        uninstall = selfHosted.mkUninstallScript { inherit (cfg) dataDir storage; };
        "uninstall:data" = selfHosted.mkUninstallScript { inherit (cfg) dataDir storage; includeData = true; };
      };
      environment = environment // {
        OLLAMA_MODELS_DECLARED = builtins.concatStringsSep " " cfg.models;
      };
    })
  ]);
}
