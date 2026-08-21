# &desc: "Session default applications -- editor (fresh), browser (vivaldi), terminal (kitty), file manager (dolphin), menu (wofi)."

{ ... }:

{
  # Session variables migrated from Hyprland
  # to global variables. Follows the goal of
  # structure and organization as the rest
  # of the project.
  config.vars.desktop.default.apps = {
    editor = "fresh";
    browser = "vivaldi";
    terminal = "kitty";
    fileManager = "dolphin";
    menu = "wofi --show drun";
  };
}
