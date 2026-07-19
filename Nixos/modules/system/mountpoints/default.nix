# &desc: "Mountpoints module schema -- disk registry/manager (UUID+addresses), activation-time bash mount resolver, wiring in ./mountpoints.nix."

{ lib, ... }:

# Schema only -- a disk registry/manager, not just an active-mount list:
# uuid is the only required field, so an entry can exist purely to record
# a UUID (and give it an addressable key) without `at` ever being set.
# The device submodule type lives in ./lib/device-type.nix (split out
# since it's sizeable). The one real definition (which disks, which
# mountpoints) lives in Nixos/config/system/mountpoints.nix. Logic that
# resolves all this into real mounts lives in ./mountpoints.nix, imported
# below -- as real activation-time bash, not the fileSystems option,
# since `as`'s LABEL/NAME resolution needs live disk access that eval
# time can't reliably get (see that file's own comment for why). The
# actual bash for that lives in real standalone .sh files under
# ./lib/resolve-leaf/ and ./lib/mount-entry/, each with a small default.nix
# wiring in the few Nix-computed values -- same split as
# modules/security/sudo-keyfile's own lib/checker/, lib/checker-stub/.
{
  imports = [ ./mountpoints.nix ];

  options.vars.system.mountpoints = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        false -- this entire module is treated as if it doesn't exist:
        no activation script contribution at all (not even an empty
        subshell), regardless of what's declared under `device`. Same
        field/semantics as config.vars.system.ports.enabled.
      '';
    };

    blocking = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Global default for whether a mount failure blocks activation
        (pacnix rebuild fails loudly instead of printing a yellow
        warning). Per-entry `device.<key>.blocking` overrides this.
      '';
    };

    device = lib.mkOption {
      type = lib.types.attrsOf (import ./lib/device-type.nix { inherit lib; });
      default = { };
      description = ''
        Known disks, keyed by whatever string you want to address them
        by later (e.g. config.vars.system.mountpoints.device.storage) -- the
        key doesn't have to be meaningful, a raw uuid works fine too.
        See ./lib/device-type.nix for the field list.
      '';
    };
  };
}
