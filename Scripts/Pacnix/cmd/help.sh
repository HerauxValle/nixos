#!/usr/bin/env bash
cat <<'EOF'
usage: pacnix <command> [args]

  rebuild [--label <text>]
      Rebuild and switch to the new NixOS config (sudo nixos-rebuild
      switch). --label appends "-<text>" to the generation's normal
      date/version label in the GRUB menu -- only if given, otherwise
      the label is left as the plain default.

  validate
      Dry-run the rebuild (sudo nixos-rebuild dry-build) -- shows what
      would change, builds nothing, switches nothing.

  check
      Evaluate the flake for errors (nix flake check) -- fast, catches
      syntax/type mistakes without building anything.

  test-build
      Actually builds the full system closure (nix build, no switch) --
      catches real build failures without touching your running
      system.

  optimise
      Hardlinks duplicate files across the store to save space
      (nix-store --optimise). Pure dedup, deletes nothing. Prints
      store size before/after and Nix's own dedup-savings figure once
      it finishes -- no live spam during the run.

  orphaned
      Removes store paths unreferenced by any current or past
      generation (nix-collect-garbage, no --delete-older-than --
      doesn't touch generation history/rollback, only genuinely unused
      paths). Same before/after reporting as optimise.

  reload
      Runs the fish `reload` function (syncs fish/bash/nu/pwsh configs),
      `qsr` (relaunches MyBar), and `hyprctl reload`. Warns and does
      nothing if fish/qsr/hyprctl aren't found instead of half-running.
      Also reloads kitty's config (`kitty @ load-config`), but only from
      inside a kitty window -- silently skipped otherwise, best-effort.

  store <name>
      Finds nix store paths for a package name -- what's in the current
      system's closure right now, and separately, the highest version
      anywhere in /nix/store (may differ -- not garbage collected yet,
      etc.). e.g. pacnix store firefox

  info [-o FIELD1,FIELD2,...] [-n] [-p]
      Exhaustive, machine-parsable system report -- 124 fields across
      15 categories: Packages, Store, Generations, Flake, System, Disk,
      Btrfs, NixConfig, GC, Hardware, Boot, Network, Security, Health,
      Session. Package provenance (system vs home-manager vs imperative
      vs full closure), store internals (derivations vs built outputs,
      fixed-output/network-fetched derivation count, top 5 largest
      packages, top 5 most-duplicated), exact flake pins, nix.conf and
      GC settings, btrfs allocation (not just df), systemd/journal
      health, network/firewall state, and more -- most of it well
      beyond what any single stock command gives you.
        -o LIST   select/order fields (like lsblk -o), `-o list` to
                  see all available fields, grouped, with descriptions
        -n        values only, no labels, one per line
        -p        KEY="value" pairs (like lsblk -P), eval-able
      A full run takes several seconds (multiple nix eval calls, a full
      closure walk, store-wide scans) -- `-o` a handful of cheap fields
      if you just need something fast.
      e.g. pacnix info -o STORE_SIZE,PKGS_SYSTEM -p

  help
      Show this message.
EOF
