# &desc: "Nix flake packaging ltree as a stdenv derivation (plain gcc build, no per-file compilation) plus a devShell with gcc/gdb/valgrind for local hacking."
{
  description = "LTree - blazing fast recursive tree, line/char counter, JSON exporter";

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
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "ltree";
          version = "0.2.0";

          # ---- local, non-git use (current default) ----
          # This is a plain local directory: `nix build`/`nix develop`
          # read straight off disk, no git commit or remote needed. The
          # tradeoff is the usual flake one -- untracked files are
          # invisible to Nix's copy of `./.` even locally, since flakes
          # only ever see the filtered `self` (git-ignored/untracked
          # files excluded) once the directory becomes an actual git
          # repo. As long as this stays a plain folder (no `.git` here
          # at all), that filtering doesn't apply and `./.` is just
          # "everything in this directory".
          src = ./.;

          # ---- git use (swap in if this ever moves to a remote) ----
          # Uncomment this block and delete/comment the `src = ./.;`
          # line above once the project lives in an actual git repo
          # you push to. `rev` pins an exact commit/tag so the build is
          # reproducible from anywhere, not just this machine.
          #
          # src = pkgs.fetchFromGitHub {
          #   owner = "REPLACE_ME";      # e.g. your GitHub username
          #   repo  = "ltree";
          #   rev   = "REPLACE_ME";      # a commit hash or tag, not a branch
          #   hash  = pkgs.lib.fakeHash; # placeholder: `nix build` will
          #                              # fail and print the real
          #                              # "sha256-..." to paste in here
          # };
          #
          # Local-repo variant, if you'd rather build from whatever's
          # currently checked out (including uncommitted changes) once
          # this folder *is* a git repo, instead of a pinned remote rev:
          #
          # src = ./.;   # same line as above, but now git-aware: with an
          #               # actual .git present, Nix respects .gitignore
          #               # and only copies tracked (or at least
          #               # git-added) files instead of the whole tree.

          # No -march=native here on purpose: this derivation has to be
          # buildable (and cacheable) on whatever machine runs `nix build`,
          # not just the one that happens to build it first. Drop into
          # `nix develop` and compile with -march=native yourself for a
          # machine-local binary if you want that extra edge.
          #
          # Every .c file under src/ is compiled together into one binary
          # (see docs/architecture.md for the module map) -- there's no
          # per-file build step, just one gcc invocation over the whole
          # directory.
          buildPhase = ''
            runHook preBuild
            $CC -O3 -std=c11 -Wall -Wextra -Iinclude -o ltree src/*.c src/*/*.c
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ltree $out/bin/ltree
            runHook postInstall
          '';

          meta = {
            description = "Recursive directory tree with line/char counts, permissions, size, hashing, diffing, and JSON export";
            mainProgram = "ltree";
          };
        };

        # `nix develop` gives you gdb + valgrind alongside gcc, same
        # toolchain used to verify the shipped binary is leak-free.
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.gcc
            pkgs.gdb
            pkgs.valgrind
          ];
        };
      }
    );
}
