{ config, pkgs, ... }:

let
  cfg = config.vars.luks2;
in

# Unlock
{

  # usb_storage/uas: get the VirtualKeys USB drive recognized this early
  # in initrd. ext4: filesystem it's formatted with, needed to mount it.
  boot.initrd.kernelModules = [ "usb_storage" "uas" "ext4" ];

  boot.initrd.systemd = {

    enable = false;
    # initrd only ships busybox's mount by default; the script below
    # needs the real util-linux mount to handle -o ro correctly.
    initrdBin = with pkgs; [ util-linux ];

    # Mounts the VirtualKeys USB drive read-only at /key before
    # cryptsetup needs the keyfile from it.
    services.mount-usb-key = {

      # before/wantedBy cryptsetup-pre.target: systemd's own hook point
      # for "run before any LUKS unlock is attempted" -- the mechanism
      # this is supposed to rely on (see the drop-in below for why that
      # alone wasn't enough).
      wantedBy = [ "cryptsetup-pre.target" ];
      before = [ "cryptsetup-pre.target" ];
      # Wait for the initrd's own early filesystem setup before touching
      # disks -- nothing's ready to mount onto until then.
      after = [ "local-fs-pre.target" ];
      # Skip systemd's normal unit dependencies (sysinit.target etc.) --
      # they're not set up yet this early in initrd.
      unitConfig.DefaultDependencies = false;
      # Runs once (the script below) and exits; not a long-running daemon.
      serviceConfig.Type = "oneshot";

      script = ''

        mkdir -m 0755 -p /key
        for i in $(seq 1 30); do
          if [ -e "/dev/disk/by-label/${cfg.usbKeyLabel}" ]; then
            break
          fi
          sleep 0.5
        done
        mount -n -t ext4 -o ro /dev/disk/by-label/${cfg.usbKeyLabel} /key

      '';

    };

    # cryptsetup-pre.target ordering alone doesn't make
    # systemd-cryptsetup@root.service actually wait for mount-usb-key --
    # observed booting straight into the LUKS attempt before the USB
    # device even finished enumerating. systemd-cryptsetup@root.service
    # is a template-unit instance generated at runtime by
    # systemd-cryptsetup-generator, not a package-provided unit file, so
    # the default overrideStrategy (asDropinIfExists) can't detect it and
    # falls back to writing a full replacement unit -- which broke boot
    # (missing ExecStart etc, normally supplied by the generator). Forcing
    # asDropin makes this a drop-in that only adds the ordering, instead
    # of replacing the generated unit.
    services."systemd-cryptsetup@${cfg.luksDeviceName}" = {
      after = [ "mount-usb-key.service" ];
      wants = [ "mount-usb-key.service" ];
      overrideStrategy = "asDropin";
    };

  };

  boot.initrd.luks.devices.${cfg.luksDeviceName} = {

    keyFile = "/key/${cfg.keyFileName}";
    # Must match root.key's actual byte size -- systemd-cryptsetup reads
    # exactly this many bytes from the file as the key.
    keyFileSize = 4096;

  };

}
