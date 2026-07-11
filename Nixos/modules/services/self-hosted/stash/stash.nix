{ config, lib, pkgs, ... }:

# Wiring only -- the package build is ./package.nix, the generic systemd
# plumbing is ../self-hosted.nix. This file's only job is tying those
# together with this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.stash;

  package = import ./package.nix { inherit pkgs; } { inherit (cfg) version hash; };

  # Stash writes into several subdirectories of dataDir on its own, but
  # never creates them itself -- same mkdir set the old runtime.sh did
  # before every start.
  dataSubdirs = [ "plugins" "scrapers" "metadata" "cache" "generated" "blobs" ];

in

{
  config = lib.mkIf cfg.enable (selfHosted.mkSelfHostedService {
    name = "stash";
    user = config.vars.username;
    execStart = "${package}/bin/stash --host ${cfg.host} --port ${toString cfg.port}";
    preStart = [ "mkdir -p ${lib.concatMapStringsSep " " (d: "${cfg.dataDir}/${d}") dataSubdirs}" ];
    inherit (cfg) dataDir storage autoStart environment;
  });
}
