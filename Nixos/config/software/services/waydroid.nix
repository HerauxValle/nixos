# &desc: "Waydroid / android emulator"

{ pkgs, ... }:
{
  virtualisation.waydroid.enable = true;
  virtualisation.waydroid.package = pkgs.waydroid-nftables;

  # waydroid.cfg has no NixOS module option -- it's a plain ini file
  # waydroid itself writes/rewrites, so enforce our override just
  # before each container start instead of hand-editing it once.
  # auto_adb=true enables adb over TCP automatically instead of
  # manually toggling service.adb.tcp.port each session.
  #
  # NOTE: suspend_action is NOT what stops the container from
  # freezing when its UI window is hidden -- hardware_manager.py's
  # suspend() only branches on suspend_action == "stop" (session
  # stop) vs. anything else (always freezes, "ignore" is not a real
  # value). The actual freeze trigger is Android's own guest-side
  # power manager calling that suspend hardware request once its
  # screen goes idle. Preventing that requires disabling screen
  # sleep from inside Android over adb (svc power stayon true +
  # screen_off_timeout) -- see tmp.sh, this can't be done
  # declaratively since it needs an authorized adb connection.

  systemd.services.waydroid-container.serviceConfig.ExecStartPre = [
    "-${pkgs.gnused}/bin/sed -i -e 's/^auto_adb = .*/auto_adb = True/' /var/lib/waydroid/waydroid.cfg"
    "-${pkgs.gnused}/bin/sed -i -e 's/^ro.debuggable=.*/ro.debuggable=1/' /var/lib/waydroid/rootfs/system/build.prop"
  ];
}
