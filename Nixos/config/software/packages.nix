{
  pkgs,
  inputs,
  ...
}:

{
  config.vars.environment = {
    sources = {
      kde = pkgs.kdePackages;
      qt5 = pkgs.libsForQt5;
      qt6 = pkgs.qt6Packages;
      python = pkgs.python3Packages;

      custom = {
        claudeCode = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

        mybarBackend = pkgs.callPackage ../../../Quickshell/MyBar/backend.nix { };

        crun = inputs.crun.packages.${pkgs.stdenv.hostPlatform.system}.default;

        ltree = inputs.ltree.packages.${pkgs.stdenv.hostPlatform.system}.default;

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

    packages = {
      pkgs = {

        # Browsers
        vivaldi = { };

        # Development
        git = { };
        neovim = { };

        # Languages & SDKs
        python3 = { };
        go = { };
        rustc = { };
        cargo = { };
        zig = { };
        swift = { };
        dotnet-sdk = { };

        # Build tools
        gcc = { };
        gnumake = { };
        cmake = { };
        meson = { };
        pkg-config = { };

        # Nix
        nil = { };

        # Shells
        fish = { };
        nushell = { };
        powershell = { };
        quickshell = { };

        # CLI utilities
        curl = { };
        fastfetch = { };
        tree = { };
        eza = { };
        fzf = { };
        zoxide = { };
        ripgrep = { };
        cloc = { };

        # Desktop
        grim = { };
        slurp = { };
        wl-clipboard = { };
        awww = { };
        mangohud = { };

        # Media
        mpv = { };
        oculante = { };

        # Security & Filesystems
        mkpasswd = { };
        e2fsprogs = { };
        mtools = { };
        ntfs3g = { };
        btrfs-progs = { };
        tpm2-tools = { };

        # Shell tooling
        shellcheck = { };
        bash-language-server = { };
      };

      custom = {
        claudeCode = { };
        mybarBackend = { };
        kittyWrapped = { };
        crun = { };
        ltree = { };
      };

      kde = {

        # File management
        dolphin = { };
        kio-extras = { };
        kio-admin = { };
        kservice = { };
        polkit_gnome = { };

        # Media
        gwenview = { };

        # Theming
        breeze = { };
        breeze-icons = { };
        qtstyleplugin-kvantum = { };

        # Neovim tooling
        stylua = { };
        shfmt = { };
        black = { };

        lazygit = { };
        lazydocker = { };
        fd = { };

        lua-language-server = { };
        pyright = { };
        rust-analyzer = { };
        gopls = { };
        clang-tools = { };
        marksman = { };
        yaml-language-server = { };
        taplo = { };
        sqls = { };
        typescript-language-server = { };
        vscode-langservers-extracted = { };

        # Misc
        nodejs = { };
        unzip = { };
        zip = { };
        wget = { };
      };

      python = {
        pip = { };
      };

      qt5 = {
        qt5ct = { };
        qtstyleplugin-kvantum = { };
      };

      qt6 = {
        qt6ct = { };
      };
    };
  };
}
