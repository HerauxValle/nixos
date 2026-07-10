{ config, pkgs, ... }:

# All `programs.*` declarations from across Nixos/, gathered in one place.
# Each block below is annotated with which file it used to live in.

let
  # SDDM login/lock background -- only used by programs.silentSDDM below.
  # See modules/desktop/desktop.nix for the rest of that module.
  wallpaper = ../../../Scripts/Wallpaper/wallpaper.jpg;
  # wallpaper = null;
in
{
  # All NixOS system-level `programs.*` options, grouped into one attrset so
  # every entry has an obvious place to go instead of sprouting its own
  # top-level `programs.<x> = ...;` line. Each is annotated with which file
  # it used to live in.
  programs = {

    # --- modules/desktop/desktop.nix ---

    fish.enable = false;

    hyprland = {
      enable = false;
      withUWSM = true;
      xwayland.enable = false;
    };

    steam = {
      enable = false;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = false;
      localNetworkGameTransfers.openFirewall = true;
    };

    # Bumps CPU governor/priority while a game runs. Use via `gamemoderun %command%` in Steam launch options.
    gamemode.enable = false;
    # Micro-compositor for FSR upscaling / frame limiting / fullscreen fixes. Use via `gamescope ... -- %command%`.
    gamescope.enable = false;

    # Sets up services.displayManager.sddm itself (theme, wayland.enable,
    # extraPackages etc.) -- see flake.nix for the silent-sddm input.
    silentSDDM = {
      enable = false;
      theme = "default";

      # Filename after copy is the basename of the wallpaper path, regardless
      # of this attrset key -- see silent-sddm's nix/package.nix.
      backgrounds = if wallpaper == null then { } else { inherit wallpaper; };

      settings =
        if wallpaper == null then
          { }
        else
          {
            "LoginScreen".background = builtins.baseNameOf wallpaper;
            "LockScreen".background = builtins.baseNameOf wallpaper;
          };
    };

    # --- modules/packages/shells.nix ---

    direnv.enable = false;
    # Suppresses the "direnv: loading/using/export" status lines. This is
    # read by the direnv binary itself from /etc/direnv/direnv.toml, not
    # injected into any shell's rc -- applies the same in fish/bash/nu/pwsh
    # without touching any of them.
    direnv.silent = true;

    # --- modules/nix/settings.nix ---

    nix-ld.enable = false;

  };

  # --- home-manager user programs ---
  #
  # Some `programs.*` options only exist under home-manager, not as NixOS
  # system options (e.g. programs.fresh-editor below), so they have to be
  # reached through home-manager.users.<name>.programs like shells.nix
  # already does elsewhere -- setting them directly at this file's top
  # level would just be an unknown option and fail to evaluate. Grouped
  # here as one attrset so any future home-manager-only `programs.*` entry
  # has an obvious place to go instead of sprouting its own
  # home-manager.users.herauxvalle.programs.<x> line.
  home-manager.users.herauxvalle.programs = {

    # fresh (terminal editor). Package comes straight from nixpkgs
    # (pkgs.fresh-editor, pname "fresh", built from github:sinelaw/fresh) --
    # no extra flake input needed. Module: nix-community/home-manager,
    # modules/programs/fresh-editor.nix.
    #
    # defaultEditor = true sets EDITOR and VISUAL to "fresh" via
    # home.sessionVariables. Note: Hyprland/Config/Apps/defaults.lua also
    # sets EDITOR=fresh (matches) and VISUAL=code-oss (now
    # redundant/conflicting with this) -- left as-is since that file is out
    # of scope here.
    #
    # extraPackages below are language servers only -- confirmed against
    # fresh's own shipped defaults by running `fresh --cmd config show` and
    # reading its built-in `lsp.<language-id>` map (not guessed from docs,
    # which only list a partial table). Each id already has a matching
    # `command` baked into fresh's config, so dropping the binary on $PATH
    # is the entire integration -- no config.json entries needed for any of
    # these. auto_start is false for all of them upstream, so each server
    # still only spawns the first time you open a matching file, same as
    # any other fresh install.
    fresh-editor = {
      enable = false;
      defaultEditor = true;
      extraPackages = with pkgs; [
        rust-analyzer                    # lsp.rust
        gopls                            # lsp.go
        typescript-language-server       # lsp.javascript / lsp.typescript
        clang-tools                      # lsp.c / lsp.cpp (clangd)
        jdt-language-server              # lsp.java (jdtls)
        python3Packages.python-lsp-server # lsp.python (pylsp)
        nil                              # lsp.nix
        bash-language-server             # lsp.bash -- also covers zsh dotfiles
                                          # (.zshrc etc, routed to the bash
                                          # language by filename) and fish's
                                          # scripts get bash/sh highlighting
                                          # from the same grammar, but fish
                                          # isn't a distinct language id in
                                          # fresh's config -- no lsp.fish to
                                          # wire up.
        yaml-language-server             # lsp.yaml
        taplo                            # lsp.toml
        vscode-langservers-extracted     # lsp.json (also brings html/css servers)
        # nushell's own `nu --lsp` covers lsp.nushell -- already a system
        # package (modules/packages/installed.nix), not duplicated here.
        # PowerShell has a recognized language id but no built-in
        # lsp.powershell entry upstream, and no clean standalone nixpkgs
        # LSP binary for it (PowerShell Editor Services isn't packaged
        # that way) -- skipped.
      ];
    };

  };
}
