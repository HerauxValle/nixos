# &desc: "CPU power config -- governor forced to performance, no clock-down under light load; desktop, no battery to protect."

{ ... }:

{
  # Default was "powersave" (confirmed via /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
  # -- a real cost on a desktop with no battery to save: every load spike pays
  # a ramp-up delay from the lowest P-state instead of already sitting at
  # max clock. Same reasoning as graphics.nix's own PowerMizer override for
  # the GPU side.
  powerManagement.cpuFreqGovernor = "performance";
}
