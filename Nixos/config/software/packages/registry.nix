{
  pkgs,
  inputs,
  ...
}:

{
  config.vars.environment.sources = {
    # Standalone sources
    kde = pkgs.kdePackages;
    qt5 = pkgs.libsForQt5;
    qt6 = pkgs.qt6Packages;
    python = pkgs.python3Packages;

    # Complex custom sources
    custom = {
      claudeCode = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      mybarBackend = pkgs.callPackage ../../../../Quickshell/MyBar/backend.nix { };
      crun = inputs.crun.packages.${pkgs.stdenv.hostPlatform.system}.default;
      ltree = inputs.ltree.packages.${pkgs.stdenv.hostPlatform.system}.default;
      casket = inputs.casket.packages.${pkgs.stdenv.hostPlatform.system}.default;

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
