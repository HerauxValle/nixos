# &desc: "Docker daemon (virtualisation.docker) -- autoprune, live-restore across daemon restarts, and capped container log size. Compose/buildx CLI plugins themselves live in packages.nix, not here."

{ ... }:

{
  virtualisation.docker = {
    enable = true;

    # Unused images/containers/build cache otherwise never get reclaimed on
    # their own -- default schedule (weekly) is fine, nothing to override.
    autoPrune.enable = true;

    # Containers survive a `docker.service` restart instead of being killed
    # -- matters here specifically because any rebuild touching docker-
    # related config restarts that service.
    liveRestore = true;

    # Docker's default json-file log driver has no size cap -- a chatty
    # long-lived container can otherwise fill the disk unnoticed over time.
    daemon.settings = {
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
    };
  };
}
