# &desc: "Enables hardware.bluetooth (bluez, bluetoothctl) + blueman applet -- sixaxis plugin disabled, it fights with sc-controller's own DS4 pairing and was causing repeated USB resets on the wired controller."

{ ... }:

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.DisablePlugins = "sixaxis";
  };
  services.blueman.enable = true;
}
