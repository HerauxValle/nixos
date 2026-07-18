
{ config, lib, ... }:

{
  imports = [ ./users.nix ];

  options.vars.system.users = {
    fallbackHash = lib.mkOption {
      type = lib.types.str;
      # Default passwd will never be called or added. This is purely for someone
      # that skips install.sh -- so install.sh is not forced on someone.
      # Since this password on the general use is never set this is not a security
      # risk worth removing.
      default = "$6$RtR/fJhkE927CBnr$ODSLT/jQg4QLmLMljhT8snD9DGKoD1X8jPMXYPE4w.n0rWYoA.vCOZZhIvBnVDq2J25VotSzoF7PGW/KhT/.W0";
      description = ''
        Precomputed `mkpasswd -m sha-512 "changeme"` -- a different person's
        own password hash goes here. Written to the account's hashedPasswordFile
        only if that file is ever missing at activation time (see
        modules/system/users/users.nix); never overwrites an existing one.
      '';
    };

    # Derived fact, not procedural logic -- the real logic (the activation
    # script's bootstrap check, users.users.* assembly) stays in
    # modules/system/users/users.nix.
    hashFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.identity.secretsBaseDir}/${config.vars.identity.username}-password.hash";
      description = "Root-owned file holding the account's real password hash.";
    };
  };
}
