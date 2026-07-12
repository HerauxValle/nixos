{ config, ... }:

# Real values -- schema + the actual mount logic live in
# ../../modules/system/mountpoints/. Data only, same reasoning as every
# config/<category>/<name>.nix file.
#
# Get a disk's UUID with `lsblk -o NAME,MOUNTPOINTS,UUID,LABEL`.
{
  config.vars.mountpoints = {
    # Global default -- individual device.<key>.blocking entries below
    # override this per-drive.
    blocking = false;

    device = {
      # Real drives, all mounted under the same parent so referencing
      # code elsewhere in the repo can use
      # config.vars.mountpoints.device.<key>.path instead of hardcoding
      # /run/media/${config.vars.username}/<label> -- blocking = true
      # since a silent miss here means something else in the repo reads
      # a path that was never actually mounted.
      backup = {
        uuid = "b07f4a7d-6afe-490c-a039-1da3530b887a";
        at = "/home/${config.vars.username}/Drives";
        as = "Backup";
        owner = "${config.vars.username}:users";
        blocking = true;
      };

      storage = {
        uuid = "e5c9cfb5-e142-4da0-9877-a559ce5d9625";
        at = "/home/${config.vars.username}/Drives";
        as = "Storage";
        owner = "${config.vars.username}:users";
        blocking = true;
      };

      media = {
        uuid = "3137c041-ad4a-468b-8549-5244d19945a9";
        at = "/home/${config.vars.username}/Drives";
        as = "Media";
        owner = "${config.vars.username}:users";
        blocking = true;
      };

      # {
      #   uuid = "2d160f61-b304-459e-921b-c4f9115adc02"; # only an example UUID!
      #   at = "/mnt"; # optional -- omit for a pure registry record, nothing mounted
      #   as = "Documentation"; # optional -- omit for LABEL, or "NAME"/"UUID" to force
      #   owner = "${config.vars.username}:users"; # optional -- omit to leave as-is (root)
      #   blocking = false; # optional -- omit to inherit the global default above
      # }
    };
  };
}
