# &desc: "Prism Launcher program config -- Minecraft mod/modpack/instance launcher with real Modrinth integration, home-manager only."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory -- same reasoning as ./vscode's own
  # enable.nix). Picked over nixpkgs' modrinth-app: that one's wrap step
  # (wrapGAppsHook) is currently broken upstream
  # (wrapGAppsHookHasRunForOutput: bad array subscript, confirmed live),
  # and the unwrapped fallback crashed instantly on Hyprland (Wayland Error
  # 71, a known webkitgtk/wlroots DMA-BUF issue with that Tauri app
  # specifically) before even getting to the missing-icon-theming problem
  # skipping the wrapper causes on top. Prism Launcher is a native Qt app --
  # neither failure mode applies -- and has a real, actively maintained
  # home-manager module, unlike modrinth-app (plain package only, no
  # module).
  config.home-manager.users.${config.vars.identity.username}.programs.prismlauncher.enable = false;
}
