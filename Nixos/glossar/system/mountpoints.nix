{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.system.mountpoints option, all commented out.
# Same shape as glossar/main/variables.nix, scoped to one module. Schema:
# modules/system/mountpoints/default.nix +
# modules/system/mountpoints/lib/device-type.nix. Real values on this
# machine: config/system/mountpoints.nix. Logic that turns this into
# real mounts: modules/system/mountpoints/mountpoints.nix.
#
# A disk registry/manager, not just an active-mount list -- uuid is the
# only required field, so an entry can exist purely to record a UUID
# (and give it an addressable key, config.vars.system.mountpoints.device.<key>)
# without `at` ever being set. Real bash at activation time, not the
# fileSystems option -- `as`'s LABEL/NAME resolution needs live disk
# access eval time can't reliably get.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/system/mountpoints.nix and uncomment it there to actually set
# it.
# =========================================================================

{
  # config.vars.system.mountpoints = {

  #   # --- globals ------------------------------------------------------------
  #   enabled = true;   # false = the entire module is treated as if it doesn't exist
  #   blocking = false; # default for device.<key>.blocking

  #   device = {

  #     # --- every field, one disk -----------------------------------------
  #     storage = {
  #       uuid = "2d160f61-b304-459e-921b-c4f9115adc02"; # only an example UUID! get yours via:
  #                                                        # lsblk -o NAME,MOUNTPOINTS,UUID,LABEL
  #       enabled = true;   # false = treated as if this entry doesn't exist at all
  #       at = "/mnt";      # parent directory -- mount target is at/leaf
  #       as = "Documentation"; # leaf name -- omit for LABEL, or "NAME"/"UUID" to force
  #       owner = "${username}:users"; # chown'd onto the mount target every activation
  #       blocking = false; # null (omit) inherits the global default above
  #     };

  #     # --- pure registry record -- no `at`, nothing mounted --------------
  #     # just a UUID + addressable key, e.g. for a drive referenced
  #     # elsewhere by config.vars.system.mountpoints.device.backup.uuid without
  #     # this module ever mounting it itself.
  #     backup = {
  #       uuid = "b07f4a7d-6afe-490c-a039-1da3530b887a";
  #     };

  #   };

  # };

  # --- config.vars.system.mountpoints.device.<key>.path -- derived, not set directly ---
  # only resolves when enabled = true, at is set, and as is a literal
  # string or "UUID" (LABEL/NAME/omitted need a live disk query, so no
  # static path exists to hand back). Reference it elsewhere instead of
  # hardcoding a path string:
  #   paths.save = "${config.vars.system.mountpoints.device.storage.path}/Torrents/Library";
}
