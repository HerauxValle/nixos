# &desc: "Immich service wrapper wiring -- mkFromNativeService binding, Postgres/Redis/ML config, shared update script."

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

  cfg = config.vars.services.selfHosted.immich;

  # Shared with every other mk-from-native service's own update.nix --
  # see ../lib/mk-from-native/update.nix's own top comment (deduped
  # once this and qbittorrent's were confirmed byte-for-byte identical
  # except for these five facts).
  updateArgs = {
    name = "immich";
    package = pkgs.immich;
    githubRepo = "immich-app/immich";
    tagPrefix = "v";
    restartUnits = "immich-server immich-machine-learning";
  };
  updateScript = selfHosted.mkFromNativeUpdateScript updateArgs;
  updateApplyScript = selfHosted.mkFromNativeUpdateScript (updateArgs // { apply = true; });

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

          # commonServiceConfig (shared by every immich unit) hardcodes
          # ProtectHome = true -- real, confirmed-by-testing consequence:
          # a private mount namespace makes ALL of /home (including
          # mediaLocation, nested under it here) appear completely absent
          # to immich-server, independent of any file ownership --
          # requireMounts's own preStart mount check (also sandboxed the
          # same way, ExecStartPre shares the unit's namespace) failed
          # exactly this way on a real run ("is not mounted" even though
          # it genuinely was, confirmed from a plain root shell at the
          # same moment).
          #
          # ProtectHome = "tmpfs" + BindPaths on the exact same paths
          # requireMounts already checks is the real, tested fix -- not a
          # guess: confirmed directly (systemd-run throwaway units, this
          # session) that this combination correctly exposes the real
          # vault mount for both the mount check AND real read/write
          # access to mediaLocation's actual nested content, running
          # under the exact same hardening the real unit uses
          # (PrivateUsers, NoNewPrivileges, stripped capabilities, the
          # dedicated immich user). Also confirmed the dedicated immich
          # system user needs no additional fix beyond this -- a real,
          # separate ACL-based "grant a dedicated user traversal rights
          # into a human user's home directory" approach was designed and
          # its primitives verified this session (see
          # ../lib/acl-traversal/) but turned out unnecessary here:
          # BindPaths's own intermediate-directory construction happens
          # inside systemd's synthetic tmpfs, not the real (0700)
          # ~/herauxvalle, so the traversal problem never actually
          # applies once this fix is in place.
          #
          # Deliberately reuses requireMounts itself as the BindPaths
          # list rather than a second option -- the two lists mean
          # exactly the same thing here ("paths that must be visible to
          # this unit"), keeping them as one option instead of two that
          # could drift out of sync.
          systemd.services.immich-server.serviceConfig.ProtectHome = lib.mkForce "tmpfs";
          systemd.services.immich-server.serviceConfig.BindPaths = cfg.requireMounts;
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
      user = config.vars.identity.username;
      packages = [ pkgs.curl pkgs.jq ];
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
      };
    })
  ];
}
