# &desc: "Hardcore server's config-file overrides -- just the server-icon, no plugin configs since there are no plugins."

{ ... }:

{
  services.minecraft-servers.servers.hardcore.files."server-icon.png" = ../../icons/hardcore.png;
}
