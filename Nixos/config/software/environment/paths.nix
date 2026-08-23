# &desc: "Personal picks -- extra directories of prebuilt/unmanaged binaries (AppImages etc) added to PATH."

{ ... }:

{
  config.vars.packages.extraPaths = [
    "$HOME/Applications/WebApps"
    "$HOME/Applications/Desktop"
  ];
}
