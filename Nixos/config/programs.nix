{ pkgs, ... }:

# Personal picks that have no sensible generic default -- the gaming stack,
# silentSDDM's wallpaper, and the editor+LSP list. fish/hyprland/direnv/
# nix-ld stay as real defaults in modules/packages/programs/default.nix
# since the rest of this repo already assumes them regardless of who's
# cloning it. See that file for the schema this fills in.
{
  config.vars.programs = {
    steam = {
      enable = false;
      remotePlayOpenFirewall = true;
      localNetworkGameTransfersOpenFirewall = true;
    };

    gamemode.enable = false;
    gamescope.enable = false;

    silentSDDM = {
      enable = false;
      wallpaper = ../../Scripts/Wallpaper/wallpaper.jpg;
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
        # package (Nixos/config/packages.nix), not duplicated here.
        # PowerShell has a recognized language id but no built-in
        # lsp.powershell entry upstream, and no clean standalone nixpkgs
        # LSP binary for it (PowerShell Editor Services isn't packaged
        # that way) -- skipped.
      ];
    };
  };
}
