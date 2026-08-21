# &desc: "Package sources registry -- kde/qt5/qt6/python from nixpkgs, custom sources from flakes (claude-code, claude-desktop, casket, ltree, crun, kitty with libxkbcommon wrapper)."

{
  pkgs,
  inputs,
  ...
}:

{
  config.vars.packages.environment.sources = {
    # Standalone sources
    kde = pkgs.kdePackages;
    qt5 = pkgs.libsForQt5;
    qt6 = pkgs.qt6Packages;
    python = pkgs.python3Packages;

    # Complex custom sources
    custom = {
      claudeCode = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      # This flake (patrickjaja/claude-desktop-bin) has no "-fhs" output --
      # unlike the previous aaddrick/claude-desktop-debian source, it
      # doesn't sandbox via buildFHSEnv at all; it substitutes nixpkgs'
      # own (already NixOS-patched) electron derivation and wraps qemu/
      # virtiofsd/OVMF in directly. MCP servers (npm/uvx-installed,
      # dynamically linked against system libs) are handled by nix-ld,
      # already configured system-wide on this machine.
      claudeDesktop =
        inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
      mybarBackend = pkgs.callPackage ../../../../Quickshell/MyBar/backend.nix { };
      crun = inputs.crun.packages.${pkgs.stdenv.hostPlatform.system}.default;
      ltree = inputs.ltree.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # Keyed "cas" (not "casket") because the alias mechanism in
      # packages.nix (the "@obi" on this package's version key) matches
      # a bin/ file literally named after this attribute -- see
      # lib/wrap-aliased.nix. The flake/project itself is still called
      # Casket; only the binary and this key are "cas".
      cas = inputs.casket.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # Opposite of "cas" above: keyed "seed" (matching the flake's own
      # pname and its bin/seed) with "sd" added as the alias in
      # packages.nix instead, since "sd" is the short muscle-memory name
      # here rather than the project's own name.
      seed = inputs.seed.packages.${pkgs.stdenv.hostPlatform.system}.default;

      # kitty dlopen()s libxkbcommon at runtime for keysym-name lookups
      # (shifted symbol keybinds like ctrl+dollar/asterisk/exclam).
      # libxkbcommon is loaded dynamically, so it must be injected into
      # LD_LIBRARY_PATH manually.
      kittyWrapped = pkgs.kitty.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/kitty \
            --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.libxkbcommon ]}
        '';
      });
    };
  };
}
