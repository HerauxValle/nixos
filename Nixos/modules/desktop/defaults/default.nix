# &desc: "Desktop default applications schema -- terminal/fileManager/menu/browser/editor option definitions, imports sessionVariables.nix."

{ lib, ... }:

with lib;

{
  imports = [
    ./sessionVariables.nix
  ];

  options.vars.desktop.default.apps = {
    terminal = mkOption {
      type = types.str;
      default = "kitty";
      description = "Default terminal emulator.";
    };

    fileManager = mkOption {
      type = types.str;
      default = "dolphin";
      description = "Default file manager.";
    };

    menu = mkOption {
      type = types.str;
      default = "wofi --show drun";
      description = "Default application launcher.";
    };

    browser = mkOption {
      type = types.str;
      default = "firefox";
      description = "Default web browser.";
    };

    editor = mkOption {
      type = types.str;
      default = "nano";
      description = "Default text editor.";
    };
  };
}
