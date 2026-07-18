{ ... }:

{
  config.vars.environment.packages = {
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

      swift = {
        versions = {
          # Version pinning -- allows multiple versions per package from different commits.
          # Default gets linked to the normal PATH name. A hash can be added after # to run
          # without --impure. Adding only # outputs the hash during rebuild. No # after the
          # commit requires --impure to rebuild. One --impure run and then always pure is
          # entirly possible. Use a @ after the version to get a alias that gets added to
          # PATH as preference of the name of the binary.
          "5.10.1@swift5" = "26.11.20260629.b5aa0fb#sha256-oPXCU/SSUokcGaJREHibG1CBX3+s/W7orDWQOZDsEeQ=";
        };
        # Selects the default version for this package. All other versions are still available
        # as "<package>-<version>" in PATH. The default package is also (redundatnyl, but for)
        # consistency available as "<package>-latest"
        # IMPORTANT: The <version> needs to match one of the versions of above literally --
        # including alias!
        default = "5.10.1@swift5";
      };

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
      polkit_gnome = { };
      pinta = { };

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

    custom = {
      claudeCode = { };
      mybarBackend = { };
      kittyWrapped = { };
      crun = { };
      ltree = { };
      casket = { };
    };

    kde = {

      # File management
      dolphin = { };
      kio-extras = { };
      kio-admin = { };
      kservice = { };

      # Media
      gwenview = { };

      # Theming
      breeze = { };
      breeze-icons = { };
      qtstyleplugin-kvantum = { };
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
}
