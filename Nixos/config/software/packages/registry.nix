# &desc: "Package sources registry -- kde/qt5/qt6/python from nixpkgs, custom sources from flakes (claude-code/desktop-fhs, casket, ltree, crun, kitty with libxkbcommon wrapper)."

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
      # -fhs (not the plain "claude-desktop" output) -- MCP servers
      # (npm/uvx-installed, dynamically linked against system libs) need
      # an FHS environment on NixOS to run at all. Also this flake's own
      # "default".
      claudeDesktop =
        inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-fhs;
      mybarBackend = pkgs.callPackage ../../../../Quickshell/MyBar/backend.nix { };
      crun = inputs.crun.packages.${pkgs.stdenv.hostPlatform.system}.default;
      ltree = inputs.ltree.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # Keyed "cas" (not "casket") because the alias mechanism in
      # packages.nix (the "@obi" on this package's version key) matches
      # a bin/ file literally named after this attribute -- see
      # lib/wrap-aliased.nix. The flake/project itself is still called
      # Casket; only the binary and this key are "cas".
      cas = inputs.casket.packages.${pkgs.stdenv.hostPlatform.system}.default;

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
