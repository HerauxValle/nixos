{ config, lib, pkgs, ... }:

# Wiring only -- but unlike every other service, there's no package.nix
# here (pkgs.immich comes straight from nixpkgs, no pin of our own -- see
# default.nix's own version comment) and the live units
# (immich-server, immich-machine-learning, postgresql, redis-immich)
# are built entirely by services.immich itself, not by
# mkSelfHostedService. This file's job is exactly what it is for every
# other service -- tie this framework's own conventions to this
# service's real config values -- just through
# ../lib/mk-from-native/services.nix instead of ../lib/service/
# mk-self-hosted-service.nix.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.immich;

  updateScript = import ./lib/update.nix { inherit pkgs; };
  updateApplyScript = import ./lib/update.nix { inherit pkgs; apply = true; };

in

{
  config = lib.mkMerge [
    (selfHosted.mkFromNativeService {
      enabled = cfg.enabled;
      requireMounts = cfg.requireMounts;
      # Only immich-server actually touches mediaLocation -- the ML
      # sidecar's own env (see the wrapped module's own
      # machine-learning.environment) never references it at all, so it
      # has no reason to wait on the same vault mount.
      mountCheckUnits = [ "immich-server" ];
      extraConfig = lib.mkMerge [
        {
          services.immich = {
            enable = false;
            database.enable = false;
            redis.enable = false;
            mediaLocation = cfg.mediaLocation;
            environment = cfg.environment;
            machine-learning.enable = cfg.enableMachineLearning;
            machine-learning.environment = cfg.machineLearningEnvironment;
          }
          // lib.optionalAttrs (cfg.host != null) { host = cfg.host; }
          // lib.optionalAttrs (cfg.port != null) { port = cfg.port; }
          // lib.optionalAttrs (cfg.environmentFile != null) { secretsFile = cfg.environmentFile; };

          # Real data (43GB, confirmed) at mediaLocation is root:root,
          # inherited from the old bash framework's install -- the
          # wrapped module's own tmpfiles rule
          # (systemd.tmpfiles.settings.immich."${mediaLocation}".e) only
          # *adjusts* mediaLocation's own ownership, never recurses into
          # its contents (upload/, library/, thumbs/, profile/,
          # encoded-video/, backups/ -- each still root:root even after
          # that rule runs). Recursive `Z` fixes the whole tree, every
          # activation, idempotent -- exactly what the wrapped module's
          # own mediaLocation doc comment says is required for a
          # non-default path ("the directory has to be created manually
          # such that the immich user is able to read and write to it").
          systemd.tmpfiles.rules = [
            "Z ${cfg.mediaLocation} 0700 ${config.services.immich.user} ${config.services.immich.group} - -"
          ];

          # services.immich hardcodes wantedBy = [ "multi-user.target" ]
          # on immich-server -- no autoStart-equivalent option exists
          # natively. mkForce wins over that unconditioned definition so
          # cfg.autoStart actually has an effect, matching every other
          # service's own autoStart semantics.
          systemd.services.immich-server.wantedBy =
            lib.mkForce (lib.optionals cfg.autoStart [ "multi-user.target" ]);
        }
        (lib.mkIf cfg.enableMachineLearning {
          systemd.services.immich-machine-learning.wantedBy =
            lib.mkForce (lib.optionals cfg.autoStart [ "multi-user.target" ]);
        })
      ];
    })
    (selfHosted.mkActionService {
      name = "immich";
      enabled = cfg.enabled;
      user = config.vars.username;
      packages = [ pkgs.curl pkgs.jq ];
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
      };
    })
  ];
}
