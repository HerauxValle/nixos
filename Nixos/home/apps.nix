# &desc: "Symlinks home-manager XDG config directories to Dotfiles subdirs (Hyprland, Kitty, Mpv, Neovim, Scripts, Fastfetch, etc)."

{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}:

let
  # Mime types routed to a single default app -- one genAttrs call per
  # category instead of repeating the same desktop file on every line.
  imageMimeTypes = [
    "image/png"
    "image/jpeg"
    "image/webp"
    "image/gif"
    "image/bmp"
    "image/tiff"
    "image/avif"
    "image/heic"
    "image/svg+xml"
  ];
  videoMimeTypes = [
    "video/mp4"
    "video/x-matroska"
    "video/webm"
    "video/quicktime"
    "video/mpeg"
    "video/x-msvideo"
    "video/ogg"
  ];
  textMimeTypes = [ "text/plain" ];

  defaultAppsByType = mimeTypes: desktopFile: lib.genAttrs mimeTypes (_: [ desktopFile ]);
in
{
  # x-scheme-handler/magnet -- overrides the stock qBittorrent GUI
  # package's own org.qbittorrent.qBittorrent.desktop (installed only for
  # its icon/window, see packages.nix), which would otherwise win the
  # magnet association and launch a second, unrelated qBittorrent
  # instance under this user instead of reaching the real one
  # (qbittorrent-nox, running as its own system user -- see
  # config/self-hosted/qbittorrent.nix). qbit-magnet (Scripts/QbitMagnet,
  # wired onto PATH in config/software/environment/scripts.nix) forwards
  # the URI to that instance's WebUI API instead.
  xdg.desktopEntries.qbit-magnet = {
    name = "qBittorrent (magnet handler)";
    exec = "qbit-magnet %u";
    terminal = false;
    noDisplay = true;
    mimeType = [ "x-scheme-handler/magnet" ];
  };
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    # Pre-existing associations, previously set imperatively (whatever
    # app/dolphin's "always use this" dialog wrote straight into
    # ~/.config/mimeapps.list) -- folded in here so home-manager can own
    # the file outright instead of refusing to touch it.
    "x-scheme-handler/mailto" = [ "vivaldi-stable.desktop" ];
    "x-scheme-handler/claude-cli" = [ "claude-code-url-handler.desktop" ];
    "x-scheme-handler/claude" = [ "com.anthropic.Claude.desktop" ];

    "x-scheme-handler/magnet" = [ "qbit-magnet.desktop" ];

    # Default browser. Without an explicit default here, xdg-open falls
    # back to the first entry for x-scheme-handler/http(s) in
    # mimeinfo.cache (nixpkgs' generated app registry, ordered by package
    # registration, not by anything configured) -- on this system that
    # happened to be Tor Browser instead of Vivaldi.
    "text/html" = [ "vivaldi-stable.desktop" ];
    "x-scheme-handler/http" = [ "vivaldi-stable.desktop" ];
    "x-scheme-handler/https" = [ "vivaldi-stable.desktop" ];
    "x-scheme-handler/about" = [ "vivaldi-stable.desktop" ];
    "x-scheme-handler/unknown" = [ "vivaldi-stable.desktop" ];
  }
  // defaultAppsByType imageMimeTypes "org.kde.gwenview.desktop"
  // defaultAppsByType videoMimeTypes "mpv.desktop"
  // defaultAppsByType textMimeTypes "code.desktop";
  xdg.configFile."mimeapps.list".force = true;

  xdg.configFile = {
    "hypr".source = ../../Hyprland;
    "kitty".source = ../../Kitty;
    "mpv".source = ../../Mpv;
    "quickshell".source = ../../Quickshell;
    "uwsm/env-hyprland".source = ../../Hyprland/Uwsm/env-hyprland;

    # Neovim configuration itself is declarative and tracked in Dotfiles.
    # Plugins, Mason packages, Treesitter parsers, caches, logs, etc. live
    # under ~/.impure/neovim/, keeping generated/editor-managed state out of
    # the repository while allowing the config to rebuild the environment.
    "nvim".source = ../../Neovim;

    # Not Hyprland-specific (Pacnix, Run, Reload, etc. are general-purpose),
    # so it's its own top-level folder/XDG dir, same pattern as the others.
    "scripts".source = ../../Scripts;

    # Same plain copy as everything else above. theme.py (run manually,
    # live -- see Scripts/Reload/theme.py) writes config.jsonc and
    # colors.env straight into Dotfiles/Fastfetch/; this just picks up
    # whatever's there at rebuild time, same as any other dotfile.
    "fastfetch".source = ../../Fastfetch;

    # Gwenview's canvas fill (app/gvcore.cpp) builds its palette from
    # KColorSchemeManager, reading the active .colors file directly -- not
    # qt6ct's palette at all. Stock BreezeDark has zero alpha anywhere in it,
    # so no color-scheme setting alone makes that fill translucent. This is
    # BreezeDark with alpha added to just [Colors:View] BackgroundNormal
    # (traced: with a dark scheme + Dark mode, gvcore.cpp uses that color
    # directly, no swap), used only by Gwenview via its own ColorScheme key.
    "gwenviewrc" = {
      force = true;
      # gwenview had already written its own copy imperatively;
      # home-manager refuses to clobber existing files otherwise.
      text = ''
        [General]
        BackgroundColorMode=DocumentView::Dark

        [UiSettings]
        ColorScheme=BreezeDarkTransparent
      '';
    };

  };

  xdg.dataFile = {
    "color-schemes/BreezeDarkTransparent.colors".source =
      ../../Themes/Gwenview/BreezeDarkTransparent.colors;

    # Declarative Proton GE: symlinks nixpkgs' proton-ge-bin into Steam's compat
    # tools dir. Version is whatever nixpkgs pins; bumps on flake update + rebuild,
    # no protonup/imperative download step needed. Force-check the tool in
    # Properties > Compatibility after a version bump.
    "Steam/compatibilitytools.d/GE-Proton".source = pkgs.proton-ge-bin;
  };

  # gamdl reads/rewrites ~/.gamdl/config.ini (configparser INI, not JSON --
  # see gamdl/cli/config_file.py) and adds any of its own missing default
  # keys back into the file on every run, which fails if the file is a
  # read-only symlink into the Nix store. Copy it in via activation instead
  # of xdg.configFile so it stays a normal writable file gamdl can update.
  home.activation.gamdlConfig =
    let
      gamdlConfigIni = pkgs.writeText "gamdl-config.ini" (
        lib.generators.toINI { } {
          gamdl = {
            cookies_path = "${config.home.homeDirectory}/.config/gamdl/cookies.txt";
            wvd_path = "${config.home.homeDirectory}/.config/gamdl/device.wvd";
            output_path = "${config.home.homeDirectory}/Music/AppleMusic";
            # "piority" is not a typo -- it matches gamdl's actual (typo'd)
            # CliConfig field name; the correct spelling gets silently
            # dropped as an unknown key and reset to gamdl's default.
            song_codec_piority = "alac";
            download_mode = "ytdlp";
            cover_format = "jpg";
            album_folder_template = "{artist}/{album}";
            single_disc_file_template = "{track:02d} - {title}";
          };
        }
      );
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      install -Dm644 ${gamdlConfigIni} "$HOME/.gamdl/config.ini"
    '';

  # ~/Applications/Desktop holds hand-placed/imperative .desktop files (e.g.
  # per-instance Prism Launcher shortcuts) -- not tracked in Dotfiles, and
  # its contents aren't knowable at eval time (readDir on it is impure and
  # flakes reject that). MyBar's appscanner
  # (Quickshell/MyBar/source/appscanner/appscanner.cpp) only lists files
  # directly inside $XDG_DATA_HOME/applications (it doesn't recurse into
  # subdirectories), so each file gets symlinked at the top level of
  # applications/ individually, at activation time, rather than a single
  # symlinked subfolder (which it would walk past silently).
  home.activation.linkDesktopApps = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    desktopDir="${osConfig.vars.identity.homeDirectory}/Applications/Desktop"
    appsDir="${osConfig.vars.identity.homeDirectory}/.local/share/applications"
    if [ -d "$desktopDir" ]; then
      for f in "$desktopDir"/*.desktop; do
        [ -e "$f" ] || continue
        run ln -sf "$f" "$appsDir/$(basename "$f")"
      done
    fi
  '';
}
