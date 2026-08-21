# &desc: "Two-tier swap, added 2026-08-09 after two back-to-back hard crashes traced to zero swap + heavy JVM memory pressure on a 16GB-RAM machine -- zram (8GB, 50%, zstd) as the fast first tier, a 16GB disk swapfile (1:1 with physical RAM) as overflow."

{ ... }:

{
  config.vars.system.swap = {
    enabled = true;
    disk.sizeMiB = 16384; # 1:1 with physical RAM
    zram = {
      enabled = true;
      memoryPercent = 50; # 8GB on this 16GB machine
      algorithm = "zstd";
    };
  };
}
