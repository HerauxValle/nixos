# &desc: "Waydroid / android emulator"

{ pkgs, ... }:
{
  virtualisation.waydroid.enable = true;
  virtualisation.waydroid.package = pkgs.waydroid-nftables;
  environment.systemPackages = [ pkgs.android-tools ];
}
