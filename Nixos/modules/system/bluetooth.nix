# &desc: "Enables hardware.bluetooth (bluez, bluetoothctl) + blueman applet."

{ ... }:

{
  hardware.bluetooth = {
    enable = false;
    powerOnBoot = true;
  };
  services.blueman.enable = false;
}
