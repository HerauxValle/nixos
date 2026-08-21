# &desc: "Enables hardware.bluetooth (bluez, bluetoothctl) + blueman applet."

{ ... }:

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;
}
