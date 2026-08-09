# &desc: "Hardcore server's config-file overrides -- server-icon, and BlueMap's accept-download + fog-of-war (min-inhabited-time) + full cave removal (remove-caves-below-y) so the web map can't reveal unexplored terrain OR let free-flight explore caves you haven't actually found."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore.files = {
    "server-icon.png" = ../../icons/hardcore.png;

    "plugins/BlueMap/core.conf" = {
      format = pkgs.formats.json { };
      value = {
        accept-download = true;
      };
    };

    # Two layers, both needed -- min-inhabited-time alone isn't enough:
    # once a chunk's surface has been visited it passes that check, but
    # the whole vertical column (including caves you never mined into)
    # still renders, and BlueMap's 3D viewer's free-flight camera can
    # fly straight through walls to see it. remove-caves-below-y set
    # absurdly high (10000) strips cave geometry from the render
    # entirely, everywhere, regardless of visited status -- there's
    # nothing there to fly into even with free-flight on, since the data
    # was never included in the first place. Map id defaults to the
    # world folder name -- "world" here, matching server.nix's
    # level-name.
    "plugins/BlueMap/maps/world.conf" = {
      format = pkgs.formats.json { };
      value = {
        min-inhabited-time = 1;
        remove-caves-below-y = 10000;
      };
    };
  };
}
