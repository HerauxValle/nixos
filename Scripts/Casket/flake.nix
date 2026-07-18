# &desc: "Nix flake packaging cas as a rustPlatform.buildRustPackage derivation plus a devShell with cargo/rustc for local hacking."
{
  description = "cas - encrypted vault manager (LUKS2 + btrfs, optional 2FA keyfile)";

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
      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "cas";
          version = "2.0.0";
          src = ./.;

          cargoLock.lockFile = ./Cargo.lock;

          # cas shells out to all of these at runtime; wrap the binary so
          # they're on PATH regardless of the caller's own environment
          # (this matters since cas re-execs itself under sudo, which on
          # some setups resets PATH to a minimal default).
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postInstall = ''
            wrapProgram $out/bin/cas --prefix PATH : ${
              pkgs.lib.makeBinPath [
                pkgs.cryptsetup
                pkgs.btrfs-progs
                pkgs.udisks2
                pkgs.util-linux # mount/umount/losetup/blkid
                pkgs.systemd # udevadm
                pkgs.e2fsprogs # debugfs -- raw keyfile reads off a removable drive, no mount needed
              ]
            }
          '';

          meta = {
            description = "Encrypted vault manager: LUKS2 image files with optional 2FA keyfile, btrfs snapshots, and safe passphrase rotation";
            mainProgram = "cas";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cargo
            rustc
            rust-analyzer
            cryptsetup
            btrfs-progs
            udisks2
            e2fsprogs
          ];
        };
      }
    );
}
