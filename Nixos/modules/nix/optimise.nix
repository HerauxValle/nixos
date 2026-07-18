
{ config, pkgs, lib, ... }:

let

  # Wraps the automatic run with before/after stats -- the stock service
  # just runs bare `nix-store --optimise`. Output lands in the journal
  # same as any systemd service: `journalctl -u nix-optimise`.

  optimiseReport = pkgs.writeShellScript "nix-optimise-report" ''

    set -euo pipefail
    before_kb=$(du -s /nix/store 2>/dev/null | cut -f1)
    before_paths=$(ls /nix/store | wc -l)
    start=$(date +%s)

    echo "=== before: $((before_kb / 1024 / 1024))G, $before_paths top-level paths ==="

    ${config.nix.package}/bin/nix-store --optimise -vv

    end=$(date +%s)
    after_kb=$(du -s /nix/store 2>/dev/null | cut -f1)
    after_paths=$(ls /nix/store | wc -l)
    saved_kb=$((before_kb - after_kb))
    pct=$(awk "BEGIN { printf \"%.2f\", ($saved_kb / $before_kb) * 100 }")

    echo "=== after: $((after_kb / 1024 / 1024))G, $after_paths top-level paths ==="
    echo "=== saved: $((saved_kb / 1024 / 1024))G ($pct%) in $((end - start))s ==="
  '';
in

{
  # Hardlinks identical files across different store paths to save space
  # -- pure dedup, deletes nothing. "daily" + the default
  # randomizedDelaySec/persistent means roughly once a day, not a fixed
  # clock time, with catch-up at next boot if the machine was off.
  nix.optimise = {
    automatic = true;
    dates = "daily";
  };

  systemd.services.nix-optimise.serviceConfig.ExecStart =
    lib.mkForce "${optimiseReport}";
}
