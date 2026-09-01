# &desc: "gamdl-wrapper schema -- options for the wrapper-v2 FairPlay decrypt daemon gamdl needs for lossless (ALAC) downloads. Imports ./gamdl-wrapper.nix for the wiring."

{ config, lib, ... }:

{
  imports = [ ./gamdl-wrapper.nix ];

  options.vars.services.gamdlWrapper = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "wrapper-v2 (https://github.com/glomatico/wrapper-v2) -- a local FairPlay decrypt daemon gamdl talks to via --use-wrapper for lossless ALAC. AAC downloads never need this. Requires Apple's own Android Apple Music native libraries staged by hand (see srcDir) -- this option alone does not make lossless work.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start gamdl-wrapper.service on boot. Off by default -- start by hand with `systemctl --user start gamdl-wrapper` when you actually want to do a lossless download.";
    };

    srcDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.identity.homeDirectory}/.gamdl/wrapper";
      description = "Writable directory holding the staged wrapper-v2 source (Dockerfile, compose.yaml, vendor AOSP libs -- restaged from the pinned Nix store copy on every rebuild) plus rootfs/system/lib64 and data/, which are real runtime state (Apple's staged .so files, session cache) and are never touched by that restaging. Lives under ~/.gamdl (gamdl's own config dir) so all of gamdl's state -- CLI config, cookies/wvd, and the wrapper -- sits in one place.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8880;
      description = "Host port for wrapper-v2's HTTP control API (/health, /login, /login/2fa, /me, /playback). Pass to gamdl as --wrapper-url http://127.0.0.1:<this>.";
    };

    decryptPort = lib.mkOption {
      type = lib.types.port;
      default = 10020;
      description = "Host port for wrapper-v2's raw TCP FPS decrypt protocol (WV2D). Pass to gamdl as --wrapper-decrypt-port.";
    };

    targetArch = lib.mkOption {
      type = lib.types.enum [ "x86_64" "arm64-v8a" ];
      default = "x86_64";
      description = "Docker build/runtime arch. Must match the Apple Music APK split staged into srcDir/rootfs/system/lib64 via gamdl-wrapper-stage-libs.";
    };
  };
}
