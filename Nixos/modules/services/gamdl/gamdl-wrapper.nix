# &desc: "gamdl-wrapper wiring -- restages the pinned wrapper-v2 source into srcDir every rebuild, a systemd --user service that docker-compose up/down's it, and the gamdl-wrapper-stage-libs helper for extracting Apple's native libs from a user-supplied Apple Music APK."

{ config, lib, pkgs, ... }:

# wrapper-v2 doesn't fit the self-hosted framework
# (modules/services/self-hosted) -- that framework assumes a pinned,
# Nix-buildable version+hash (a binary fetch or a pip lock). wrapper-v2's
# image build needs the user's own, non-redistributable Apple Music
# Android APK staged in by hand; Nix can pin everything else (the
# Dockerfile, compose.yaml, the committed AOSP vendor libs) but not that.
# So it's a small, standalone module instead of a self-hosted service.

let
  cfg = config.vars.services.gamdlWrapper;

  # Pinned wrapper-v2 source (Dockerfile, compose.yaml, Rust/C++ source,
  # tools/, committed AOSP vendor libs). Everything except Apple's own
  # .so files, which cannot be fetched declaratively -- see
  # gamdl-wrapper-stage-libs below.
  wrapperSrc = pkgs.fetchFromGitHub {
    owner = "glomatico";
    repo = "wrapper-v2";
    rev = "100e0a864e883e03a3ac450a780dd9563fff5271";
    hash = "sha256-vJekQlmEnB8q/hQKbuoFiJsksKlr83ibHuNonQBfT4k=";
  };

  stageLibsScript = pkgs.writeShellScriptBin "gamdl-wrapper-stage-libs" ''
    set -euo pipefail
    if [ $# -lt 1 ]; then
      echo "usage: gamdl-wrapper-stage-libs <path-to-apple-music.apk|.apkm> [--ignore-hash]" >&2
      echo "  extracts Apple's native libs (matched against LIBS_VERSION.json for" >&2
      echo "  ${cfg.targetArch}) into ${cfg.srcDir}/rootfs/system/lib64" >&2
      exit 1
    fi
    bundle="$1"
    shift
    exec ${pkgs.bash}/bin/bash "${wrapperSrc}/tools/extract-libs.sh" \
      --bundle "$bundle" \
      --arch ${cfg.targetArch} \
      --out "${cfg.srcDir}/rootfs/system/lib64" \
      "$@"
  '';

in
{
  config = lib.mkIf cfg.enabled {
    environment.systemPackages = [ stageLibsScript ];

    # Restage the pinned source every rebuild. No --delete: rootfs/system/lib64
    # (Apple's staged .so files) and data/ (session cache, mpl_db) are real
    # runtime state that doesn't exist in wrapperSrc at all, so a plain
    # additive rsync can never touch them.
    system.activationScripts.gamdlWrapperSrc = lib.stringAfter [ "users" ] ''
      install -d -o ${config.vars.identity.username} -g users "${cfg.srcDir}"
      ${pkgs.rsync}/bin/rsync -rlt --chmod=Du+w,Fu+w \
        --chown=${config.vars.identity.username}:users \
        "${wrapperSrc}/" "${cfg.srcDir}/"
      install -d -o ${config.vars.identity.username} -g users \
        "${cfg.srcDir}/rootfs/system/lib64" "${cfg.srcDir}/data"
    '';

    systemd.user.services.gamdl-wrapper = {
      description = "wrapper-v2 -- Apple Music FairPlay decrypt daemon for gamdl lossless (ALAC) downloads";
      after = [ "docker.service" ];
      environment = {
        TARGET_ARCH = cfg.targetArch;
        HTTP_PORT = toString cfg.httpPort;
        DECRYPT_PORT = toString cfg.decryptPort;
        # Dockerfile uses --mount=type=cache, a BuildKit-only Dockerfile
        # directive -- plain classic-builder `docker-compose up --build`
        # rejects it ("the --mount option requires BuildKit").
        DOCKER_BUILDKIT = "1";
        COMPOSE_DOCKER_CLI_BUILD = "1";
        WRAPPER_RUNTIME_TRACE = "1";
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = cfg.srcDir;
        # Invoked through `docker compose`, not the standalone
        # docker-compose binary directly -- plugin discovery (finding
        # buildx, needed for the Dockerfile's --mount=type=cache) lives in
        # the docker CLI's dispatcher, not in the compose plugin binary
        # itself when run standalone. Confirmed: standalone docker-compose
        # logs "Docker Compose requires buildx plugin to be installed" and
        # fails even with DOCKER_BUILDKIT=1 set, despite `docker info`
        # already listing buildx as a registered plugin.
        ExecStart = "${pkgs.docker}/bin/docker compose up --build --remove-orphans";
        ExecStop = "${pkgs.docker}/bin/docker compose down";
        Restart = "on-failure";
        RestartSec = 5;
      };
      wantedBy = lib.optional cfg.autoStart "default.target";
    };
  };
}
