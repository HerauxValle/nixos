# &desc: "Swap module logic -- translates config.vars.system.swap into the real swapDevices + zramSwap options, disk tier at lower priority than zram so zram fills first."

{ config, lib, ... }:

let
  cfg = config.vars.system.swap;
in
{
  config = lib.mkIf cfg.enabled {
    swapDevices = lib.optionals cfg.disk.enabled [
      {
        device = cfg.disk.path;
        size = cfg.disk.sizeMiB;
        priority = cfg.disk.priority;
      }
    ];

    zramSwap = lib.mkIf cfg.zram.enabled {
      enable = false;
      memoryPercent = cfg.zram.memoryPercent;
      algorithm = cfg.zram.algorithm;
      priority = cfg.zram.priority;
    };
  };
}
