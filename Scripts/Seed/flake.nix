# &desc: "Nix flake packaging seed (sd) as a stdenv derivation wrapping main.py + its sibling packages, plus sd-init as a proper static derivation instead of install.sh's runtime gcc build."
{
  description = "Seed (sd) - lightweight container runtime using Btrfs snapshots + Linux namespaces";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # sd-init pivot_roots into the container's own (foreign, non-Nix)
        # rootfs and becomes PID 1 there -- it can't depend on this
        # system's dynamic linker once it's chrooted in, so it has to be
        # fully static. install.sh's build_sd_init() does this at
        # install time with plain `gcc -static`, which works on Arch
        # (glibc ships its static .a by default) but fails on NixOS out
        # of the box (`cannot find -lc`) since the default gcc closure
        # has no static glibc. Building it here instead, with
        # glibc.static as an explicit buildInput, makes it a normal
        # cached derivation and removes the runtime-gcc step entirely.
        sd-init = pkgs.stdenv.mkDerivation {
          pname = "sd-init";
          version = "1.3.14";
          src = ./helpers;

          buildInputs = [
            pkgs.glibc.static
            pkgs.libcap # sys/capability.h (CAP_LAST_CAP) only -- no -lcap linking needed
          ];

          buildPhase = ''
            runHook preBuild
            gcc -Wall -Wextra -Werror -O2 -static -o sd-init sd-init.c -static
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp sd-init $out/bin/sd-init
            runHook postInstall
          '';

          meta = {
            description = "sd's PID-1 container init: namespace setup + pivot_root + seccomp + cgroup (static binary, see helpers/sd-init.c)";
            mainProgram = "sd-init";
          };
        };
      in
      {
        packages = {
          inherit sd-init;

          # Named "seed", not "sd" -- the shorter name is added as a PATH
          # alias by config.vars.packages.custom's versions/"@sd" wrapper
          # (see Nixos/config/software/packages/packages.nix), same
          # mechanism "cas"/"obi" already uses there. Deliberately does
          # NOT install the sd-priv/sd-priv-iso/sd-init privilege helpers
          # to /usr/local/lib/sd/priv -- the CLI hardcodes that absolute
          # path (lib/privilege.py) regardless of --enable-root, so `sd
          # run` and friends still need install.sh's helper-install step
          # run by hand at least once; this package only gets the `sd`
          # command itself onto PATH.
          default = pkgs.stdenv.mkDerivation {
            pname = "seed";
            version = "1.3.14";
            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildInputs = [ pkgs.python3 ];

            dontBuild = true;

            installPhase = ''
              runHook preInstall

              mkdir -p $out/opt/seed $out/bin
              cp -r . $out/opt/seed
              chmod +x $out/opt/seed/main.py
              patchShebangs $out/opt/seed

              # Deliberately excludes pkgs.sudo: NixOS's sudo needs the
              # real setuid wrapper at /run/wrappers/bin/sudo, and
              # prefixing PATH with nixpkgs' own (non-setuid) sudo
              # binary ahead of it would silently break privilege
              # escalation. Left to resolve from the ambient system
              # PATH instead. Everything else below is either
              # unprivileged or only ever invoked already-root (via
              # sudo sd-priv-iso), so wrapping it is safe.
              makeWrapper $out/opt/seed/main.py $out/bin/seed \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.coreutils
                    pkgs.util-linux # mount/umount/nsenter/losetup/findmnt/blkid
                    pkgs.procps # pgrep
                    pkgs.psmisc # fuser
                    pkgs.btrfs-progs
                    pkgs.cryptsetup
                    pkgs.e2fsprogs # mkfs.ext4
                    pkgs.iproute2
                    pkgs.iptables
                    pkgs.gcc # only needed if you build sd-init by hand later
                  ]
                }

              runHook postInstall
            '';

            meta = {
              description = "Lightweight container runtime using Btrfs snapshots + Linux namespaces";
              mainProgram = "seed";
              platforms = pkgs.lib.platforms.linux;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.python3
            pkgs.gcc
            pkgs.glibc.static
            pkgs.libcap
            pkgs.gdb
          ];
        };
      }
    );
}
