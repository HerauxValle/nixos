# &desc: "Mount wiring -- static (literal `as`/UUID) entries get real fileSystems+device-unit mounts that self-heal on late device enumeration; LABEL/NAME/omitted entries keep the old live-query activation script."

{ config, lib, pkgs, ... }:

let
  devices = config.vars.system.mountpoints.device;
  globalBlocking = config.vars.system.mountpoints.blocking;

  # Absolute paths throughout, not PATH lookups -- matches
  # modules/backup/dotfiles/dotfiles.nix's own convention (activation
  # scripts run with whatever minimal PATH the activation environment
  # happens to have, not a login shell's).
  lsblk = "${pkgs.util-linux}/bin/lsblk";
  mountBin = "${pkgs.util-linux}/bin/mount";
  mountpointBin = "${pkgs.util-linux}/bin/mountpoint";
  mkdir = "${pkgs.coreutils}/bin/mkdir";
  chown = "${pkgs.coreutils}/bin/chown";

  resolveLeafFn = import ./lib/resolve-leaf { inherit lsblk; };
  mountEntryLib = import ./lib/mount-entry {
    inherit
      lib
      mountBin
      mountpointBin
      mkdir
      chown
      globalBlocking
      ;
  };

  # Same "literal as / UUID" test lib/device-type.nix's own `path` field
  # uses -- these are the only entries with a mount target known at eval
  # time, so they're the only ones that can become real fileSystems
  # entries. Storage/Media/Backup are exactly this case (as = "Storage"
  # etc., a plain literal string).
  #
  # Why this exists at all: the old approach mounted every entry (literal
  # or not) via a one-shot activation-script `mount` call with no
  # dependency on the underlying block device. That's fine for a normal
  # reboot (device already enumerated by the time activation runs), but
  # confirmed broken live after a force-shutdown-then-cold-boot: the
  # activation script ran before /dev/sdb2 (external SATA, not the NVMe
  # root) was enumerated, `mount` failed, and nothing ever retried --
  # `mountpoint -q` on later checks still reported "not a mountpoint" but
  # nothing re-ran this activation script mid-boot to fix it, leaving an
  # empty directory that every consumer (qbittorrent's ACL preStart, in
  # this case) then failed against. A real fileSystems entry becomes a
  # genuine systemd .mount unit ordered after its own `<uuid>.device`
  # unit, which systemd activates the moment udev reports the device --
  # self-healing regardless of enumeration timing, which a bespoke
  # one-shot bash mount call can never be without reinventing udev
  # watching by hand.
  isStatic =
    entry:
    entry.enabled
    && entry.at != null
    && (
      let asVal = entry.as or null;
      in asVal != null && asVal != "LABEL" && asVal != "NAME"
    );

  staticDevices = lib.filterAttrs (_: isStatic) devices;
  dynamicDevices = lib.filterAttrs (_: e: !isStatic e) devices;

  staticFileSystems = lib.mapAttrs'
    (_key: entry: lib.nameValuePair entry.path {
      device = "/dev/disk/by-uuid/${entry.uuid}";
      fsType = "auto";
      # nofail -- same "don't block boot on a missing external drive"
      # behavior the old bash `blocking` flag gave at rebuild time, just
      # via the real systemd mechanism now. device-timeout gives the
      # drive real room to enumerate on a cold boot instead of racing it
      # once and giving up, which is the actual bug being fixed here.
      options = [ "nofail" "x-systemd.device-timeout=30s" ];
    })
    staticDevices;

  # chown is a separate concern from the mount itself -- RequiresMountsFor
  # (not just After=) so this unit only ever runs once the real device is
  # mounted there, never against the plain pre-existing directory.
  staticChownServices = lib.mapAttrs'
    (key: entry: lib.nameValuePair "mountpoints-chown-${key}" {
      description = "Owner grant for the ${key} mountpoint, applied once it's mounted";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ entry.path ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${chown} -- ${lib.escapeShellArg entry.owner} ${lib.escapeShellArg entry.path}";
      };
    })
    (lib.filterAttrs (_: e: e.owner != null) staticDevices);
in

{
  # Static entries (literal `as` / "UUID", e.g. Storage/Media/Backup) --
  # real fileSystems + device-bound chown service, see isStatic's own
  # comment above for why.
  fileSystems = lib.mkIf config.vars.system.mountpoints.enabled staticFileSystems;
  systemd.services = lib.mkIf config.vars.system.mountpoints.enabled staticChownServices;

  # Dynamic entries only now (LABEL/NAME/omitted) -- real bash at
  # activation time, not the fileSystems option -- same reasoning as
  # modules/backup/dotfiles/dotfiles.nix's own excludeFiles/redactValues
  # checks: `nixos-rebuild switch` (as pacnix calls it) runs WITHOUT
  # --impure, so builtins.pathExists on a plain string path outside the
  # flake cannot reliably see the real filesystem at eval time (confirmed
  # live -- it reported a disk that was actually mounted as "missing").
  # Beyond that, `as`'s LABEL/NAME resolution fundamentally needs a live
  # disk query, which fileSystems can't do at all since its mount paths
  # must be known at eval time. Wrapped in a subshell so none of this
  # leaks into the shared global scope every other module's
  # activationScripts.*.text is concatenated into -- $mountpointsFailed is
  # local to that subshell too, but its exit code is checked right after
  # and re-thrown into the outer scope, which is what actually makes a
  # blocking entry abort `pacnix rebuild` instead of every module's
  # activationScripts.*.text just running regardless.
  #
  # lib.optionalString, not lib.mkIf -- system.activationScripts.<name>.text
  # is types.lines with no default, so mkIf false would drop the
  # definition entirely instead of contributing "" (same trap documented
  # in modules/services/self-hosted/dotfiles.nix and
  # modules/system/port-forwarding/port-forwarding.nix's own UPnP step).
  # config.vars.system.mountpoints.enabled = false here means genuinely zero
  # activation-script contribution, not even an empty subshell.
  system.activationScripts.mountpoints.text = lib.optionalString config.vars.system.mountpoints.enabled ''
    (
      mountpointsFailed=0
      ${resolveLeafFn}
      ${mountEntryLib.functions}
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList mountEntryLib.call dynamicDevices)}
      [ "$mountpointsFailed" -eq 0 ]
    ) || exit 1
  '';
}
