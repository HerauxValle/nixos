# &desc: "Symlinks shell config files from Dotfiles (Fish, Nu, Pwsh, Bash)."

{ ... }:

{
  xdg.configFile = {
    "fish".source = ../../Shells/Fish;
    "nushell".source = ../../Shells/Nu;
    "powershell/Microsoft.PowerShell_profile.ps1".source =
      ../../Shells/Pwsh/Microsoft.PowerShell_profile.ps1;
  };

  home.file.".bashrc".source = ../../Shells/Bash/bashrc;
}
