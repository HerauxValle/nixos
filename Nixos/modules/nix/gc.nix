{ config, pkgs, ... }:

{

  # Removes orphaned store paths (unreferenced by any current or past
  # generation) on a schedule. Doesn't touch generation history/rollback —
  # that only happens if you also add --delete-older-than or similar.
  
  nix.gc.automatic = true;

}
