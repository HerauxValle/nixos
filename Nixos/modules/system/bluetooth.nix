# &desc: "Enables hardware.bluetooth (bluez, bluetoothctl) + blueman applet -- sixaxis plugin disabled (fights with sc-controller's own DS4 pairing, was causing repeated USB resets on the wired controller); hidp kernel module force-loaded (confirmed via dmesg: without it, a Bluetooth DS4's HID profile 'connects' at the D-Bus level but the kernel never creates an actual input device)."

{ ... }:

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.DisablePlugins = "sixaxis";
  };
  services.blueman.enable = true;

  # Not auto-loaded on this system for some reason -- module aliases
  # normally pull it in on demand, but a Bluetooth DS4's HID profile
  # connection silently produced zero input device until this was loaded
  # by hand (confirmed live via dmesg: the "Wireless Controller" input
  # nodes only appeared after `modprobe hidp`).
  boot.kernelModules = [ "hidp" ];
}
