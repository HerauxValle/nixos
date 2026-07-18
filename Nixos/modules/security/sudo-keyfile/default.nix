
{ config, lib, ... }:

# Plain facts, same convention as boot/luks2's usbKeyLabel/keyFileName --
# not a generic reusable option, just this machine's actual settings. Logic
# that reads these lives in ./sudo-keyfile.nix, imported below.
{
  imports = [ ./sudo-keyfile.nix ];

  options.vars.security.sudoKeyfile = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Master switch for keyfile-based passwordless sudo. Opt-in: this machine's own real value lives in Nixos/config/config.nix.";
    };

    keyfilePath = lib.mkOption {
      type = lib.types.str;
      default = "/run/media/${config.vars.identity.username}/VirtualKeys/auth.key";
      description = "Location of the sudo auth keyfile on the mounted USB stick.";
    };

    # Below: derived facts, not procedural logic -- the real logic
    # (wrapperPath's wrapper-dir reference, checker/checkerStub
    # derivations, the activation script, PAM rule) stays in
    # modules/security/sudo-keyfile.nix.

    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = config.vars.identity.secretsBaseDir;
      description = "Root-owned directory holding this module's hash/conf files.";
    };

    hashFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.security.sudoKeyfile.secretsDir}/${config.vars.identity.username}-sudo-keyfile.hash";
      description = "Stored SHA-256 of the keyfile's content, checked on every sudo call.";
    };

    confFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.security.sudoKeyfile.secretsDir}/${config.vars.identity.username}-sudo-keyfile.conf";
      description = "Stored device identity (label/UUID + relative path) for no-mount reads.";
    };
  };
}
