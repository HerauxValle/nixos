# &desc: "Vesktop enable -- home-manager programs.vesktop.enable, the Discord client Vencord's config lives inside."

{ config, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vesktop.enable = true;
}
