{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/searxng/. Data only, same as
# ollama.nix/stash.nix.
{
  config.vars.selfHosted.searxng = {
    # true = installed: systemd unit exists, preStart's src/venv/theme
    # reconciliation runs. false = torn down on the next rebuild --
    # venvDir, srcDir, and dataDir (minus the settings.yml symlink)
    # removed automatically; the real settings.yml inside the vault is
    # never touched by that teardown.
    enabled = true;

    # Plain, always-available -- holds nothing on its own but the
    # generated secret-key file and the settings.yml symlink.
    dataDir = "${config.vars.homeDirectory}/Applications/Networking/SearXNG";

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild. Same as every other service on
    # this machine right now.
    autoStart = false;

    # searxng/searxng's master HEAD as of this port -- no coreHash
    # alongside this (see default.nix's top comment for why: srcDir is a
    # plain writable git clone, not a fetchFromGitHub store path).
    coreRev = "c19d86faa393bdd696a5708e3c294f956d750683";

    environment = { };

    # The one real data location -- a single-file symlink, not a
    # directory, straight into the SelfHosted Casket vault. The real,
    # hand-customized settings.yml (instance name, plugins, engine
    # toggles, default_theme -- all of it) was recovered from the old
    # bash framework's configuration/settings/settings.yml (never
    # vault-backed there) and copied in by hand before the first
    # rebuild. Nix never reads or writes its contents.
    storage = [
      { src = "settings.yml"; dest = "${config.vars.homeDirectory}/Images/SelfHosted/SearXNG/settings.yml"; }
    ];

    requireMounts = [
      "${config.vars.homeDirectory}/Images/SelfHosted"
    ];

    # Empty -- dataDir holds nothing but the generated secret-key file
    # and the settings.yml symlink itself, so the default "everything
    # but storage" teardown (when enabled = false) is safe as-is.
    teardownPaths = [ ];

    # Both real, hand-crafted theme sources from the old
    # configuration/themes/ -- "adversarial" is a genuinely custom dark
    # theme (Playfair Display/JetBrains Mono, red-on-paper palette),
    # "simple" is the stock-derived default. settings.yml's own
    # ui.default_theme (inside the vault file above, untouched by this
    # port) is what actually picks between them -- currently "simple".
    # SearXNG's own /preferences page already lets any user override
    # this per-session natively, so there's no separate Nix-level
    # `theme` option here on purpose.
    themes = [
      { name = "simple"; path = ./searxng/themes/simple; }
      { name = "adversarial"; path = ./searxng/themes/adversarial; }
    ];
  };
}
