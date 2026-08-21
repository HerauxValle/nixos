# &desc: "Swap module schema -- zram (compressed RAM swap, fast tier) + a btrfs disk swapfile (larger overflow tier), wiring in ./swap.nix. The one real definition lives in Nixos/config/system/swap.nix."

{ lib, ... }:

{
  imports = [ ./swap.nix ];

  options.vars.system.swap = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        false (default) -- neither tier below exists, same as this
        module not existing at all. true -- enables whichever of
        disk.enabled / zram.enabled are also true.
      '';
    };

    disk = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Disk-backed swapfile tier -- via the real swapDevices option
          (NixOS's own module handles btrfs's NOCOW/no-compression/
          preallocation requirements correctly for a plain device+size
          on a btrfs root, no manual chattr/mkswap needed). Lower
          priority than zram below, so the kernel only spills here once
          zram's compressed capacity is full.
        '';
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/swapfile";
        description = "Where the swapfile lives -- must be on a btrfs filesystem.";
      };

      sizeMiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8192;
        description = "Swapfile size in MiB.";
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "swapDevices priority -- must be lower than zram.priority so zram fills first.";
      };
    };

    zram = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Compressed RAM-backed swap tier (zramSwap module) -- fast
          first line of absorption for a memory spike, before ever
          touching disk swap. NixOS's own zramSwap defaults
          (memoryPercent = 50, algorithm = "zstd") are exactly this
          module's own defaults below, so leaving these at default
          matches that.
        '';
      };

      memoryPercent = lib.mkOption {
        type = lib.types.ints.positive;
        default = 50;
        description = "zramSwap.memoryPercent -- zram device size as a percent of total physical RAM.";
      };

      algorithm = lib.mkOption {
        type = lib.types.str;
        default = "zstd";
        description = "zramSwap.algorithm -- compression algorithm.";
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "zramSwap.priority -- must be higher than disk.priority so zram fills first.";
      };
    };
  };
}
