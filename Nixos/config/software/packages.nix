{ config, pkgs, inputs, ... }:

# Variables
let
  claudeCode = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  mybarBackend = pkgs.callPackage ../../../Quickshell/MyBar/backend.nix { };

  # kitty dlopen()s libxkbcommon at runtime for keysym-name lookups (shifted
  # symbol keybinds like ctrl+dollar/asterisk/exclam) -- that's not a normal
  # linked dependency, so listing libxkbcommon in systemPackages alone never
  # helps; NixOS doesn't add packages' lib/ outputs to the dynamic loader's
  # search path. Has to be wired in directly via LD_LIBRARY_PATH on kitty itself.
  kittyWrapped = pkgs.kitty.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/kitty --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.libxkbcommon ]}
    '';
  });
in

# Packages
{
  environment.systemPackages = with pkgs; [

    # General
    vivaldi                     # Browser
    # vscode -- now declarative, see home-manager.users.<user>.programs.vscode
    # in Nixos/config/programs.nix (package comes from that module instead)
    git                         # Github
    curl                        # Curl
    kittyWrapped                # Terminal (wrapped: see kittyWrapped above for why)
    claudeCode                  # Claude
    mpv                          # Video player (was installed on Arch, missing here)
    oculante                     # Image viewer (was installed on Arch, missing here)

    # Languages
    python3                     # Python

    # Tools
    awww                        # Background
    grim                        # Screenshot
    slurp                       # Selection
    wl-clipboard                # Clipboard
    fastfetch                   # Fetch
    tree                        # Tree
    eza                         # Colorized ls replacement, used by ls alias in alias.fish
    mangohud                    # FPS/frametime/temp overlay, use via `mangohud %command%` in Steam
    zoxide                      # Frecency-based cd, used by cd.fish
    fzf                         # Interactive picker, used by cd.fish's `run -i`
    mkpasswd                    # Used by Scripts/Secrets/cmd/passwd.sh (secrets passwd)
    e2fsprogs                   # debugfs -- no-mount ext4 keyfile read, modules/security/sudo-keyfile.nix
    mtools                      # mcopy -- no-mount FAT/FAT32 keyfile read, modules/security/sudo-keyfile.nix
    ntfs3g                      # ntfscat -- no-mount NTFS keyfile read, modules/security/sudo-keyfile.nix
    btrfs-progs                 # btrfs restore -- no-mount btrfs keyfile read, modules/security/sudo-keyfile.nix
    tpm2-tools                  # TPM tooling
    ripgrep                     # For "todo tree" vscode extension

    # Shells
    fish                        # Main
    nushell                     # Data
    powershell                  # Windows
    quickshell                  # Aesthetic

  ] ++ (with pkgs.kdePackages; [

    dolphin                     # Explorer
    kio-extras                  # Addons
    kio-admin                   # Elevated permissions
    polkit_gnome                # Polkit agent for elevated permissions -- GUI prompt
    kservice                    # kbuildsycoca6 -- was only ever reachable via its nix store path,
                                # not on PATH, so KIO's own automatic cache-refresh calls silently failed
    gwenview                    # Image viewer

    # Theming
    breeze                      # Looks
    breeze-icons                # Icons
    qtstyleplugin-kvantum       # Kvantum

  ]) ++ (with pkgs.libsForQt5; [

    # Theming
    qt5ct                       # QT5
    qtstyleplugin-kvantum       # Kvantum (Qt5 variant)

  ]) ++ (with pkgs.qt6Packages; [

    # Theming
    qt6ct                       # QT6

  ]) ++ (with pkgs; [

    mybarBackend                 # MyBar's mybar-* backend binaries (same recipe as scripts/build/compile.sh)

  ]);
}
