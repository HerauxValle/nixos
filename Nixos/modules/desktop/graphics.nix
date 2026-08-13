# &desc: "NVIDIA graphics configuration -- open=false, modesetting=true, 32-bit support enabled, powerManagement for suspend/resume."

{ config, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # Without this, VRAM state isn't preserved across suspend -- confirmed
  # live root cause of a real crash: resume from a 2026-08-13 15:20->16:21
  # suspend logged repeated "Failed to initialize semaphore for plane
  # fence" / "Failed to apply atomic modeset. Error code: -11" / "Flip
  # event timeout", then an actual Xid 13 (Graphics Exception) that
  # SIGABRT'd Hyprland. uwsm auto-restarted it, but that respawn logged
  # "No config file found; attempting to generate" instead of loading the
  # real lua config -- the "no hyprland config after wake" symptom was
  # this driver crash's fallout, not a config bug. This wires up
  # nvidia-suspend/nvidia-resume.service + NVreg_PreserveVideoMemoryAllocations,
  # NVIDIA's own documented fix for exactly this failure mode.
  hardware.nvidia.powerManagement.enable = true;

  # PowerMizer defaults to "Adaptive" (clocks down aggressively under low
  # load, common cause of stutter on the proprietary driver going idle-clock
  # then having to ramp back up). This registry dword combo is NVIDIA's own
  # documented way to force "Prefer Maximum Performance" unconditionally --
  # PerfLevelSrc=0x2222 pins both AC and battery perf-level source to the
  # max entry in the GPU's clock table, PowerMizerLevel/-Default/-DefaultAC=0x1
  # select that same max-performance level for the three PowerMizer contexts
  # (system default, AC, and the live PowerMizerLevel itself). Applies at
  # driver load, kernel module parameter -- not per-session, not something
  # gamemode's occasional GPU bump ([[config/software/programs/gamemode]],
  # AMD-only anyway) covers.
  boot.extraModprobeConfig = ''
    options nvidia NVreg_RegistryDwords="PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerLevel=0x1; PowerMizerDefault=0x1; PowerMizerDefaultAC=0x1"
  '';
}