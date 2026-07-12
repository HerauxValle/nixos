{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.selfHosted.searxng option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/searxng/default.nix. Real values
# on this machine: config/self-hosted/searxng.nix. Full reference
# (systemd units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/searxng/info.md.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/searxng.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.selfHosted.searxng = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = torn down
  #   # automatically on the next rebuild (see teardownPaths below), not
  #   # just absent.
  #   enabled = false;

  #   # --- plain base dir -- holds only the settings.yml symlink --
  #   dataDir = "${homeDirectory}/Applications/Networking/SearXNG";

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   # --- pinned git rev -- no coreHash alongside this, srcDir is a plain writable clone --
  #   coreRev = "c19d86faa393bdd696a5708e3c294f956d750683";

  #   # --- exported as SEARXNG_SECRET -- overrides settings.yml's server.secret_key --
  #   # (a real, native override -- searx/settings_defaults.py's SettingsValue)
  #   secret = "314159265314159265";

  #   # --- passthrough env for the live process -----------------------------
  #   environment = { };

  #   # --- vault-backed real data -- a single FILE symlink, not a directory --
  #   # the real, hand-customized settings.yml. Nix never reads/writes its contents.
  #   storage = [
  #     { src = "settings.yml"; dest = "${homeDirectory}/Images/SelfHosted/SearXNG/settings.yml"; }
  #   ];

  #   # --- must already be a mountpoint before this service (or its preStart) runs --
  #   requireMounts = [ "${homeDirectory}/Images/SelfHosted" ];

  #   # --- what enabled=false actually removes -------------------------------
  #   # Empty (the default) means "everything under dataDir except storage"
  #   # -- safe here since dataDir holds nothing but the settings.yml symlink itself.
  #   teardownPaths = [ ];

  #   # --- real theme sources (Dotfiles/Themes/Searxng/, not Nixos/config/) --
  #   # symlinked into the live checkout every start.
  #   themes = [
  #     { name = "simple"; path = ../../../Themes/Searxng/simple; }
  #     { name = "adversarial"; path = ../../../Themes/Searxng/adversarial; }
  #   ];

  # };
}
