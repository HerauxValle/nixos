# &desc: "GRUB implementation -- quiet boot suppresses kernel/systemd/udev console output, applies theme path and resolution."

{ config, pkgs, ... }:

let
  cfg = config.vars.boot.grub;
in

# General
{
  # Quiet boot: keep the kernel/systemd/udev console output suppressed
  # so nothing prints over the theme while it's visible. loglevel=3 only
  # allows errors and above through; the rest silence the specific
  # subsystems (systemd's own [ OK ] status lines, udev's device-probe
  # spam) that loglevel alone doesn't cover.
  boot.kernelParams = [

    "quiet"
    "loglevel=3"
    "systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"

    # Documented cause of this exact symptom (xhci_hcd reset-looping a
    # full-speed device behind a hub): tickless/high-res timers.
    "nohz=off"
    "highres=off"

  ];

  # Newest available kernel -- Arch (no USB hub reset-loop there) was on 7.0.12.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Same intent as the kernelParams above, applied to the console itself
  # and to the initrd's own systemd instance specifically.
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;

  boot.loader = {

    timeout = if cfg.hidden then 0 else 5;
    efi.canTouchEfiVariables = true;

    grub = {

      enable = true;
      # "nodev": EFI-only install -- don't write GRUB to a disk's MBR/boot
      # sector, only to the EFI System Partition.
      device = "nodev";
      efiSupport = true;
      gfxpayloadEfi = "keep";
      gfxmodeEfi = cfg.gfxResolution;
      theme = if cfg.graphical then cfg.grubThemePath else null;

      # nixpkgs defaults this to its own dark-gray/NixOS-logo wallpaper
      # (nix-wallpaper-simple-dark-gray_bootloader.png) and installs it as
      # /boot/background.png unconditionally, underneath whatever theme is
      # set. That default image is what stays on screen the moment GRUB's
      # theme/menu layer stops rendering (Enter pressed, loading the
      # kernel/initrd) -- it's not part of the custom theme, it's the base
      # layer under it. Setting this to null skips installing it.
      splashImage = null;

      extraConfig = ''

        ${if cfg.hidden then "set timeout_style=hidden" else ""}
        ${if cfg.graphical then "terminal_output gfxterm" else "terminal_output console"}

      '';
    };
  };
}
