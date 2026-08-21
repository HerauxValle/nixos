# &desc: "ACL write grant wiring -- separate oneshot units per target, strict Before ordering, same PrivateUsers-namespace fix as acl-traversal."

{ config, lib, pkgs, ... }:

# Wiring only -- for every unit key in vars.selfHosted.aclWriteGrants
# (each service's own wiring file sets its own
# vars.services.selfHosted.aclWriteGrants.<name>, the key already being
# the unit name), a real, SEPARATE systemd oneshot unit per target unit
# (acl-write-<unit>.service, not a preStart line appended onto
# <unit>.service itself) runs mkAclWrite's preStartScript, ordered
# strictly before <unit>.service via Before=+RequiredBy=. Same shape as
# ../acl-traversal/acl-traversal.nix -- see its own top comment for why
# a real, separate unit (not a preStart append) is load-bearing here too.
# lib.mapAttrs' directly on aclWriteGrants (no lib.groupBy needed, unlike
# acl-traversal's own flat list -- the key here already groups by unit).
let
  selfHosted = import ../../self-hosted.nix { inherit lib pkgs; };
in
{
  config.systemd.services = lib.mapAttrs'
    (unit: grants: lib.nameValuePair "acl-write-${unit}" {
      description = "ACL write grants for ${unit}, applied before it starts";
      before = [ "${unit}.service" ];
      requiredBy = [ "${unit}.service" ];
      path = [ pkgs.acl ];
      script = lib.concatMapStringsSep "\n"
        (grant:
          (selfHosted.mkAclWrite {
            inherit (grant) group path;
            grant = true;
          }).preStartScript)
        grants;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
      };
    })
    config.vars.services.selfHosted.aclWriteGrants;
}
