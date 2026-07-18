# &desc: "VSCode configuration -- extensions, keybindings, and settings from Dotfiles/VSCode; personal setup with Nix, Python, Rust, C++ tooling."

{ config, pkgs, ... }:

# -------------------------------------------------------------------------
# IMPORTANT: Defaults need to be wired into modules/packages/default.nix
# first to add programs here!
# -------------------------------------------------------------------------

# Personal picks that have no sensible generic default -- the gaming stack,
# silentSDDM's wallpaper, and the editor+LSP list. fish/hyprland/direnv/
# nix-ld stay as real defaults in modules/packages/programs/default.nix
# since the rest of this repo already assumes them regardless of who's
# cloning it. See that file for the schema this fills in.
{
  # Home-manager-only programs.* (not NixOS system options, so they can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this file) -- grouped under one users.${...}.programs
  # block since vscode won't be the last personal pick to land here.
  config.home-manager.users.${config.vars.identity.username}.programs = {
    vscode = {
      enable = false;
      mutableExtensionsDir = false;
      # `code --install-extension` can no
      # longer add anything outside the list
      # below -- add here and rebuild instead.
      profiles.default = {
        # Paths, not attrsets -- keeps the files' own comments/section
        # headers intact instead of flattening them through the JSON
        # serializer.
        userSettings = ../../../VSCode/settings.json;
        keybindings = ../../../VSCode/keybindings.json;
        extensions =
          (with pkgs.vscode-extensions; [
            # --- Original Extensions ---
            bbenoist.nix
            gruntfuggly.todo-tree
            jnoortheen.nix-ide
            ms-python.debugpy
            ms-python.python
            ms-python.vscode-pylance
            ms-python.vscode-python-envs
            pkief.material-icon-theme
            # Already handles your Rust LSP (rust-analyzer)
            rust-lang.rust-analyzer

            # --- C / C++ ---
            # C/C++ IntelliSense, debugging, and code browsing
            ms-vscode.cpptools
            # twxs.cmake         # (Optional) Uncomment if you use CMake

            # --- Go ---
            # Rich Go language support (uses gopls)
            golang.go

            # --- HTML / CSS / Web Development ---
            # HTML CSS Support
            ecmel.vscode-html-css
            formulahendry.auto-close-tag
            formulahendry.auto-rename-tag
            # bradlc.vscode-tailwindcss # (Optional) Uncomment if you use Tailwind CSS

            # --- General Productivity & Nix Integration ---
            # Loads development environment shell (highly recommended)
            mkhl.direnv
            # Standardizes editor configs across teams
            editorconfig.editorconfig
            # Opinionated code formatter (highly recommended)
            esbenp.prettier-vscode
            # Supercharged Git visualization (highly recommended)
            eamodio.gitlens

            # --- JSON, YAML, & Configs ---
            # Dictates strict formatting for JSON, JSONC, and markdown
            esbenp.prettier-vscode

            # Rich JSON Schema validation, autocompletion, and YAML support
            redhat.vscode-yaml
          ])
          ++ [
            # --- Custom Marketplace Extensions ---
            (pkgs.vscode-utils.extensionFromVscodeMarketplace {
              publisher = "dustypomerleau";
              name = "rust-syntax";
              version = "0.6.1";
              sha256 = "0rccp8njr13jzsbr2jl9hqn74w7ji7b2spfd4ml6r2i43hz9gn53";
            })
            (pkgs.vscode-utils.extensionFromVscodeMarketplace {
              publisher = "coopermaruyama";
              name = "nix-embedded-languages";
              version = "2.1.0";
              sha256 = "1vr5njvzxck2nx6gqw0zfghnjpwcmvli9fwx8cqj3sgk9283ya9r";
            })
          ];
      };
    };
  };

  config.vars.packages.programs = {
    steam = {
      enable = false;
      remotePlayOpenFirewall = true;
      localNetworkGameTransfersOpenFirewall = true;
    };

    # dconf configuration engine. Essential layer for standard XDG desktop portals
    # and modular environment daemons (like polkit-gnome-authentication-agent-1)
    # running in minimal Wayland sessions. Without this registry enabled, core
    # GTK/GIO dialog wrappers fail to look up user preference paths, falling back
    # to raw un-themed white default layouts rather than honoring global systemd
    # environment settings or customized dark-mode themes.
    dconf.enable = false;

    gamemode.enable = false;
    gamescope.enable = false;

    silentSDDM = {
      enable = false;
      wallpaper = ../../../Scripts/Wallpaper/wallpaper.jpg;
    };

    # fresh (terminal editor). Package comes straight from nixpkgs
    # (pkgs.fresh-editor, pname "fresh", built from github:sinelaw/fresh) --
    # no extra flake input needed. Module: nix-community/home-manager,
    # modules/programs/fresh-editor.nix.
    #
    # defaultEditor (in modules/packages/programs/default.nix) sets EDITOR
    # and VISUAL to "fresh" via home.sessionVariables. Note:
    # Hyprland/Config/Apps/defaults.lua also sets EDITOR=fresh (matches)
    # and VISUAL=code-oss (now redundant/conflicting with this) -- left
    # as-is since that file is out of scope here.
    #
    # extraPackages below are language servers only -- confirmed against
    # fresh's own shipped defaults by running `fresh --cmd config show` and
    # reading its built-in lsp.<language-id> map (not guessed from docs,
    # which only list a partial table). Each id already has a matching
    # command baked into fresh's config, so dropping the binary on $PATH is
    # the entire integration -- no config.json entries needed for any of
    # these. auto_start is false for all of them upstream, so each server
    # still only spawns the first time you open a matching file, same as
    # any other fresh install.
    freshEditor = {
      enable = false;
      extraPackages = with pkgs; [
        rust-analyzer # lsp.rust
        gopls # lsp.go
        typescript-language-server # lsp.javascript / lsp.typescript
        clang-tools # lsp.c / lsp.cpp (clangd)
        jdt-language-server # lsp.java (jdtls)
        python3Packages.python-lsp-server # lsp.python (pylsp)
        nil # lsp.nix
        bash-language-server # lsp.bash -- also covers zsh dotfiles
        # (.zshrc etc, routed to the bash
        # language by filename) and fish's
        # scripts get bash/sh highlighting
        # from the same grammar, but fish
        # isn't a distinct language id in
        # fresh's config -- no lsp.fish to
        # wire up.
        yaml-language-server # lsp.yaml
        taplo # lsp.toml
        vscode-langservers-extracted # lsp.json (also brings html/css servers)
        # nushell's own `nu --lsp` covers lsp.nushell -- already a system
        # package (Nixos/config/packages.nix), not duplicated here.
        # PowerShell has a recognized language id but no built-in
        # lsp.powershell entry upstream, and no clean standalone nixpkgs
        # LSP binary for it (PowerShell Editor Services isn't packaged
        # that way) -- skipped.
      ];
    };
  };
}
