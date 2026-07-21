# &desc: "Personal system packages by source -- pkgs/custom/kde/qt5/qt6/python, version pinning for swift, lists ~100 tools across dev/languages/build/shell/cli/media/security."

{ ... }:

{
  config.vars.packages.environment.packages = {
    pkgs = {

      # Browsers
      vivaldi = { };

      # Development
      git = { };
      neovim = { };
      kopia = { };
      kopia-ui = { };

      # Languages & SDKs
      python3 = { };
      ruff = { };
      mypy = { };
      go = { };
      golangci-lint = { };
      delve = { };
      rustc = { };
      cargo = { };
      rustfmt = { };
      clippy = { };
      zig = { };
      typescript = { };
      prettier = { };
      eslint = { };

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
      gdb = { };
      valgrind = { };

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
      jq = { };

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
      youtube-tui = { };
      freetube = { };

      # Security & Filesystems
      mkpasswd = { };
      seahorse = { };
      e2fsprogs = { };
      mtools = { };
      ntfs3g = { };
      btrfs-progs = { };
      tpm2-tools = { };

      # Virtualization
      qemu = { };
      virtiofsd = { };
      OVMF = { };
      docker-compose = { };
      docker-buildx = { };
      dive = { }; # inspect an image layer-by-layer to find what's bloating its size
      ctop = { }; # htop-style live dashboard for running containers
      hadolint = { }; # actual Dockerfile linter
      trivy = { }; # scans images for known CVEs
      skopeo = { }; # inspect/copy/sign images across registries, no daemon needed
      act = { }; # run GitHub Actions workflows locally via Docker

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
      xclip = { };
      yt-dlp = { };

      # Fonts
      noto-fonts-color-emoji = { };
      noto-fonts = { };
      noto-fonts-cjk-sans = { };
    };

    custom = {
      claudeCode = { };
      claudeDesktop = { };
      mybarBackend = { };
      kittyWrapped = { };
      crun = { };
      ltree = { };

      # `cas` was named `obi` (ObiLock) before the Casket rename --
      # "obi" is kept as a muscle-memory alias via the versions/"@alias"
      # mechanism (see packages/docs/README.txt) -- not a second build.
      cas = {
        versions = {
          "2.0.0@obi" = "";
        };
        default = "2.0.0@obi";
      };

      # Package/attribute is "seed" (matches the flake's own pname and
      # bin/seed); "sd" is added as the short PATH alias via the same
      # versions/"@alias" mechanism `cas`/`obi` above uses. Only puts the
      # `sd` CLI on PATH -- the privilege helpers (sd-priv/sd-priv-iso/
      # sd-init) still need install.sh --enable-root run by hand at
      # least once, since the CLI hardcodes their path as
      # /usr/local/lib/sd/priv (see Scripts/Seed/flake.nix's own comment).
      seed = {
        versions = {
          "1.3.14@sd" = "";
        };
        default = "1.3.14@sd";
      };
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
