# &desc: "Enables hardware.bluetooth (bluez, bluetoothctl) + blueman applet -- sixaxis plugin disabled via bluetoothd --noplugin (fights with sc-controller's own DS4 pairing, was causing repeated USB resets on the wired controller); hidp kernel module force-loaded (confirmed via dmesg: without it, a Bluetooth DS4's HID profile 'connects' at the D-Bus level but the kernel never creates an actual input device)."

{ config, ... }:

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # `settings.General.DisablePlugins` (a main.conf key) is NOT how this
  # BlueZ version disables plugins -- confirmed live in the journal:
  # "Unknown key DisablePlugins for group General in
  # /etc/bluetooth/main.conf", meaning that setting was silently ignored
  # this whole time and sixaxis was never actually off. The real
  # mechanism is bluetoothd's own --noplugin=<name> CLI flag (see
  # `bluetoothd --help` / man bluetoothd), so it has to go on ExecStart
  # via a systemd override instead.
  systemd.services.bluetooth.serviceConfig.ExecStart = [
    ""
    "${config.hardware.bluetooth.package}/libexec/bluetooth/bluetoothd -f /etc/bluetooth/main.conf --noplugin=sixaxis"
  ];

  # Not auto-loaded on this system for some reason -- module aliases
  # normally pull it in on demand, but a Bluetooth DS4's HID profile
  # connection silently produced zero input device until this was loaded
  # by hand (confirmed live via dmesg: the "Wireless Controller" input
  # nodes only appeared after `modprobe hidp`).
  boot.kernelModules = [ "hidp" ];
}
