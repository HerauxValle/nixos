# &desc: "NVIDIA graphics configuration -- open=false, modesetting=true, 32-bit support enabled, powerManagement for suspend/resume."

{ config, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = false;
  hardware.graphics.enable = false;
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
  hardware.nvidia.powerManagement.enable = false;

  # PowerMizer defaults to "Adaptive" (clocks down aggressively under low
  # load, common cause of stutter on the proprietary driver going idle-clock
  # then having to ramp back up). This registry dword combo is NVIDIA's own
  # documented way to force "Prefer Maximum Performance" unconditionally.
  # Applies at driver load, kernel module parameter -- not per-session, not
  # something gamemode's occasional GPU bump
  # ([[config/software/programs/gamemode]], AMD-only anyway) covers.
  #
  # Card is an RTX 3060 (GA106, desktop, no battery -- `nvidia-smi
  # --query-gpu=name` confirmed) on driver 595.84, proprietary module
  # (hardware.nvidia.open = false above). Every PowerMizer-relevant
  # NVreg_RegistryDwords key NVIDIA documents (driver README, "Configuring
  # Power Management Support"), what it does, its full value range, and
  # whether it's actually in play on this card:
  #
  # - PowerMizerEnable (used, =0x1): master on/off for the whole PowerMizer
  #   subsystem. 0x0 = disabled (driver picks one fixed clock and never
  #   changes it -- not what we want here, that fixed clock isn't
  #   guaranteed to be the max one). 0x1 = enabled, PowerMizerLevel/
  #   -Default/-DefaultAC below then decide which level it sits at. Applies
  #   to every NVIDIA GPU generation this driver supports.
  #
  # - PerfLevelSrc (used, =0x2222): two nibble-pairs, AC in the high byte
  #   and battery in the low byte, each pair independently one of: 0x11 =
  #   "BIOS legacy" (perf level picked by whatever the vBIOS table says,
  #   ignores PowerMizerLevel entirely), 0x22 = "OS-defined" (perf level
  #   picked by PowerMizerLevel/-Default/-DefaultAC, the mode this needs to
  #   actually take effect). Only the AC nibble-pair matters on a desktop
  #   card with no battery rail, but the dword still requires all four
  #   nibbles -- 0x2222 sets both to OS-defined for consistency/safety
  #   rather than leaving the battery half meaningless-but-undefined.
  #
  # - PowerMizerLevel (used, =0x1): the *live* perf level PowerMizer is
  #   sitting at right now, only meaningful once PerfLevelSrc says
  #   OS-defined. 0x0 = Adaptive (the driver default we're overriding --
  #   clocks scale with load), 0x1 = Prefer Maximum Performance (always the
  #   top clock/voltage entry in the GPU's clock table), 0x2 = Auto
  #   (driver heuristic, similar to Adaptive but with different thresholds),
  #   0x3 = Prefer Consistent Performance (locks to a fixed mid-range clock
  #   instead of the top one -- exists mainly for GPUs with a "quiet"
  #   profile, not a target here).
  #
  # - PowerMizerDefault (used, =0x1): the level PowerMizer resets to after
  #   a driver reload/GPU reset, before anything else has had a chance to
  #   change PowerMizerLevel. Same 0x0-0x3 range as PowerMizerLevel above.
  #   Set to match PowerMizerLevel so a mid-session reset (e.g. suspend/
  #   resume re-init) doesn't quietly fall back to Adaptive.
  #
  # - PowerMizerDefaultAC (used, =0x1): same as PowerMizerDefault, but
  #   specifically the default while on AC power (as opposed to battery).
  #   Same 0x0-0x3 range. Redundant with PowerMizerDefault on a desktop
  #   permanently on AC, kept anyway since it's the documented AC-specific
  #   counterpart and costs nothing to set correctly.
  #
  # Documented PowerMizer-adjacent keys NOT set here, and why:
  # - PowerMizerLevelAC: AC-specific counterpart to PowerMizerLevel,
  #   distinct from PowerMizerDefaultAC (that one's the reset target, this
  #   one's live state) -- redundant with PowerMizerLevel on a card that's
  #   always on AC, so omitted rather than duplicating the same 0x1 a third
  #   time.
  # - EnableBrightnessControl: toggles driver-level panel brightness
  #   control via the NV-CONTROL X extension. Laptop/panel-only, this is a
  #   desktop card driving external monitors with their own OSD controls --
  #   not applicable.
  # - OverrideMaxPerf: forces the perf level cap past what the vBIOS
  #   thermal/power table normally allows. Deliberately not touched --
  #   PowerMizerLevel=0x1 already gets the documented max level within the
  #   card's own limits; going past that trades the vBIOS's safety margin
  #   for no real gain on a 3060 that isn't power/thermal-limited at stock.
  boot.extraModprobeConfig = ''
    options nvidia NVreg_RegistryDwords="PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerLevel=0x1; PowerMizerDefault=0x1; PowerMizerDefaultAC=0x1"
  '';
}