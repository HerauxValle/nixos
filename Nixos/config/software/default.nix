# &desc: "Software config imports -- programs (VSCode), services (polkit, systemd defaults), environment (scripts/shells/venvs), and packages submodules."

{ ... }:

{
  imports = [
    ./programs
    ./services
    ./environment
    ./packages
  ];
}
