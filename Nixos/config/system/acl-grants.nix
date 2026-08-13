# &desc: "ACL rx grants -- herauxvalle into Immich's Cloud/Imported dirs (700 immich:immich), Dolphin-browsable without changing Immich's own perms."

{ config, ... }:

{
  config.vars.system.aclGrants = [
    {
      user = config.vars.identity.username;
      path = "${config.vars.identity.homeDirectory}/Images/Media/Cloud";
    }
    {
      user = config.vars.identity.username;
      path = "${config.vars.identity.homeDirectory}/Images/Media/Imported";
    }
  ];
}
