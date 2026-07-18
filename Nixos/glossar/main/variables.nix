{ ... }:

# =========================================================================
# EXAMPLES -- every CUSTOM config.vars.* option this repo defines, all
# commented out, grouped into one nested block per module (same shape
# you'd actually write, not a repeated "dotfilesBackup.x" prefix per line).
# Skips vars.programs.* on purpose (fish.enable, hyprland.enable,
# steam.enable, ...) -- those are thin 1:1 mirrors of native NixOS/
# home-manager programs.* toggles, already documented on search.nixos.org /
# the home-manager manual. This file is only for the mechanisms this repo
# itself invented.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into Nixos/config/config.nix (or the
# relevant sibling file) and uncomment it there to actually set it.
# =========================================================================

{
  # config.vars = {

  #   # --- central facts -- schema: variables.nix ---------------------------
  #   username = "yourname";
  #   homeDirectory = "/home/${username}";  # derived default, usually leave unset
  #   hostName = "yourhost";
  #   timeZone = "Europe/Berlin";
  #   stateVersion = "26.05";
  #   secretsBaseDir = "/etc/nixos-secrets";
  #   gitCommitEmail = "you@example.com";

  #   # --- dotfiles GitHub backup -- schema: modules/backup/dotfiles -------
  #   dotfilesBackup = {
  #     enable = false;
  #     skipOnTest = true;
  #     dotfilesPath = "${homeDirectory}/Dotfiles";
  #     remoteUrl = "git@github.com:you/dotfiles.git";
  #     branch = "main";
  #     tagDateFormat = "+%H-%M-%S_%d.%m.%Y";
  #     excludeFiles = [ "Path/To/secrets.file" ];
  #     commitUserName = username;
  #     commitUserEmail = gitCommitEmail;
  #     useRepoCache = true;
  #     connectTimeoutSeconds = 5;
  #     logLevel = "normal";  # "normal" | "quiet" | "silent"
  #     keyType = "ed25519";
  #     colorRed = ''\033[0;31m'';
  #     colorYellow = ''\033[0;33m'';
  #     colorGreen = ''\033[0;32m'';
  #     colorReset = ''\033[0m'';
  #     border = "[dotfiles-backup] ============================================";
  #     secretsDir = "${secretsBaseDir}/github";
  #     keyComment = "${baseNameOf dotfilesPath}-backup";
  #     githubMetaApiUrl = "https://api.github.com/meta";
  #     githubSecretScanErrorCode = "GH013";
  #     hostKeyFailureMarker = "Host key verification failed";
  #     networkFailureMarker = "Could not resolve hostname|Connection timed out|Network is unreachable|No route to host";
  #     keyFile = "${secretsDir}/dotfiles-backup";
  #     knownHostsFile = "${secretsDir}/known_hosts";
  #     repoCache = "${secretsDir}/repo-cache";
  #     scrubHistoryOnExcludeChange = true;
  #     excludeHashFile = "${secretsDir}/exclude-hash";
  #     redactValues = [
  #       { file = "Path/To/file"; key = "vars.someOption"; }
  #     ];
  #     replaceValues = [
  #       { file = "Path/To/file"; find = "literal text"; replaceWith = "placeholder"; }
  #       { file = "Path/To/file"; key = "vars.someOption"; replaceWith = "placeholder"; }
  #     ];
  #   };

  #   # --- USB-gated boot: power off if the key is missing -- schema: modules/boot/usb-required
  #   usbRequired = {
  #     enable = false;
  #     usbKeyLabel = "YourUsbLabel";
  #     luksDeviceName = "root";
  #     usbCheckRetries = 10;
  #     usbCheckDelaySec = 0.5;
  #   };

  #   # --- USB-gated shutdown-on-removal -- schema: modules/security/usb-killswitch
  #   usbKillswitch = {
  #     killMode = "disabled";  # "soft" | "hard" | "disabled"
  #     usbSerialShort = "0000000000000000000";
  #   };

  #   # --- LUKS unlock via USB keyfile -- schema: modules/boot/luks2 -------
  #   luks2 = {
  #     luksDeviceName = "root";
  #     usbKeyLabel = "YourUsbLabel";
  #     keyFileName = "root.key";
  #   };

  #   # --- keyfile-based passwordless sudo -- schema: modules/security/sudo-keyfile
  #   sudoKeyfile = {
  #     enable = false;
  #     keyfilePath = "/run/media/${username}/VirtualKeys/auth.key";
  #     secretsDir = secretsBaseDir;
  #     hashFile = "${secretsDir}/${username}-sudo-keyfile.hash";
  #     confFile = "${secretsDir}/${username}-sudo-keyfile.conf";
  #   };

  #   # --- account password hash -- schema: modules/system/users -----------
  #   users = {
  #     fallbackHash = "$6$...";  # mkpasswd -m sha-512 "changeme"
  #     hashFile = "${secretsBaseDir}/${username}-password.hash";
  #   };

  #   # --- GRUB theming -- schema: modules/boot/grub ------------------------
  #   grub = {
  #     grubThemePath = ../../Path/To/theme;
  #     gfxResolution = "auto";
  #     hidden = true;
  #     graphical = true;
  #   };

  #   # --- PATH-exposed scripts -- schema: modules/packages/scripts --------
  #   scripts = [
  #     { dir = ../../Path/To/folder; include = { "main.sh" = "commandname"; }; }
  #   ];

  #   # --- declarative per-directory shells -- schema: modules/packages/shells
  #   shells = [
  #     { path = "${homeDirectory}/Project"; packages = [ pkgs.tmux ]; recursive = true; }
  #   ];

  #   # --- Hyprland plugins built from git -- schema: modules/hyprland/plugins
  #   hyprlandPlugins = [
  #     {
  #       name = "plugin-name";
  #       url = "https://github.com/you/plugin.git";
  #       rev = "0123456789abcdef0123456789abcdef01234567";
  #       hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  #       version = "0-unstable-2026-01-01";
  #       extraBuildInputs = [ ];
  #     }
  #   ];

  # };
}
