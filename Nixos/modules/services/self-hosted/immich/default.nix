{ lib, ... }:

# Schema only -- logic lives in ./immich.nix, imported below. Unlike
# every other service in this tree, Immich wraps nixpkgs' own mature
# `services.immich` module (via ../lib/mk-from-native/services.nix)
# instead of being built from scratch with mkSelfHostedService -- see
# ./info.md for the full "why" (Postgres+pgvector, Redis, the ML
# sidecar, real systemd hardening -- all already correct upstream,
# reimplementing it would just be worse, duplicated maintenance).
#
# Consequence: there's no dataDir/storage/teardownPaths/version/hash
# here, unlike every other service's default.nix. See ./info.md's
# "What's deliberately not here" for why each is genuinely absent, not
# just forgotten.
{
  imports = [ ./immich.nix ];

  options.vars.services.selfHosted.immich = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = services.immich.enable (+ .database.enable/
        .redis.enable) are wired on and the live units exist. false =
        treated as if this service doesn't exist -- no immich-server,
        no immich-machine-learning, no Postgres/Redis-for-immich units at
        all. Real data (mediaLocation, the Postgres database content) is
        never touched either way -- see info.md's "Install/uninstall of
        the package itself" for why that's safe without a teardownPaths
        mechanism the way every other service has one.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether immich-server (and immich-machine-learning, if enabled)
        start automatically on boot/rebuild. Unlike every other service,
        this isn't a native option on services.immich -- its own
        wantedBy = [ "multi-user.target" ] is hardcoded in the wrapped
        module. immich.nix force-overrides it (lib.mkForce) to actually
        honor this flag, the same way mkSelfHostedService's own autoStart
        works for every from-scratch service. false = still exists,
        still `systemctl start immich-server`-able by hand, just not
        pulled in on boot/rebuild -- matches every currently-migrated
        service's real config on this machine right now.
      '';
    };

    mediaLocation = lib.mkOption {
      type = lib.types.str;
      description = ''
        Passed straight to services.immich.mediaLocation. No sensible
        generic default (same reasoning as Ollama's version/hash having
        none) -- real value lives in config/self-hosted/immich.nix. Real,
        substantial existing data was found here this session (43GB,
        confirmed real Immich internal structure: upload/, library/,
        thumbs/, profile/, encoded-video/, backups/, each with their own
        .immich marker) -- see info.md's "Real data placement" for the
        full story, including why it's owned root:root and what that
        means for immich.nix's own tmpfiles fixup.
      '';
    };

    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional override for services.immich.host. null = its own default (\"localhost\") applies untouched. Unlike Ollama/SearXNG, no construction trick needed -- this is a real, genuinely typed option on the wrapped module already.";
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Optional override for services.immich.port. null = its own default (2283) applies untouched.";
    };

    requireMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Paths that must already be mountpoints before immich-server
        starts -- same generic mechanism every other service's
        requireMounts uses, merged in via
        ../lib/mk-from-native/services.nix. Only gates immich-server
        (the unit that actually touches mediaLocation) -- see that
        file's own comment for why immich-machine-learning doesn't need
        it too.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Passed to services.immich.secretsFile. Real, typed option
        (rather than an assumed hardcoded path the way Jellyfin's is) --
        Immich's own secretsFile has real semantics beyond a generic
        env-var passthrough (a KEY=VALUE file for `_secret`-style
        settings substitution, per the wrapped module's own doc comment).
        CAUTION, confirmed by reading the wrapped module directly: unlike
        this framework's own environmentFile convention everywhere else
        (EnvironmentFile = "-''${path}", a leading "-" makes a missing file
        a non-error), the native module sets
        EnvironmentFile = mkIf (cfg.secretsFile != null) cfg.secretsFile
        with **no** "-" prefix -- pointing this at a file that doesn't
        exist yet is a hard unit-start failure, not a silent no-op. Only
        set this once the file genuinely already exists (`secrets
        self-hosted immich`, same command every other service uses).
        null = unset (the current real value -- nothing needs it yet,
        the unix-socket Postgres/Redis defaults don't require one).
      '';
    };

    enableMachineLearning = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Thin pass-through to services.immich.machine-learning.enable -- face recognition / smart search. false also skips immich.nix's own autoStart override for that unit (nothing to override if it doesn't exist).";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Pass-through to services.immich.environment -- same shape as every other service's environment option.";
    };

    machineLearningEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Pass-through to services.immich.machine-learning.environment.";
    };
  };
}
