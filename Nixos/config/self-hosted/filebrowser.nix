{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/filebrowser/. Data only, same as
# ollama.nix/stash.nix.
{
  config.vars.services.selfHosted.filebrowser = {
    # true = installed: systemd unit exists. false = torn down on the
    # next rebuild -- dataDir (minus the "data" storage entry) removed
    # automatically; the real BoltDB inside the vault is never touched
    # by that teardown.
    enabled = true;

    # Plain, always-available -- holds nothing on its own, it's just
    # where the storage symlink below lands.
    dataDir = "${config.vars.identity.homeDirectory}/Applications/Networking/FileBrowser";

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild. Same as every other service on
    # this machine right now.
    autoStart = false;

    host = "127.0.0.1";
    port = 8090;

    # Faithful port of the original FB_ROOT="$HOME" -- browses the whole
    # home directory, not scoped down. Only actually applied if the
    # BoltDB doesn't exist yet (see filebrowser.nix's preStart) -- the
    # real, recovered database below already has this baked in from
    # before, so this is effectively documentation of what it already is,
    # not something this rebuild changes.
    root = config.vars.identity.homeDirectory;

    # Update together -- see
    # ../../modules/services/self-hosted/filebrowser/default.nix for how
    # to get a new hash when bumping version.
    version = "2.63.18";
    hash = "sha256-zVmcNK+tDo5hxXfRBhyCC8y3/qo8WkR3oS21hqHNk/8=";

    environment = { };

    # The one real data location -- inside the SelfHosted Casket vault,
    # same vault Stash/OpenWebUI use. dataDir/data -> this, so
    # FileBrowser's actual BoltDB lives vault-protected while dataDir
    # itself stays a plain path. The recovered pre-Nix filebrowser.db
    # (originally at the never-vault-backed ~/.config/filebrowser/, found
    # on the Media backup drive) was copied here by hand before the first
    # rebuild, so real users/settings from before carry forward instead
    # of a fresh install silently generating a new default admin.
    storage = [
      { src = "data"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/FileBrowser"; }
    ];

    # Independent fact, not derived from storage above -- they happen to
    # agree because this is the vault storage points into, not because
    # one is computed from the other.
    requireMounts = [
      "${config.vars.identity.homeDirectory}/Images/SelfHosted"
    ];

    # Empty -- dataDir holds nothing but the storage symlink itself, so
    # the default "everything but storage" teardown (when enabled =
    # false) is safe as-is; no need to scope it down further.
    teardownPaths = [ ];
  };
}
