# &desc: "Mountpoint entry wiring -- one shared bash function (mount-entry.sh) instead of mount-entry.nix's old per-entry inlined text; same decisions, same escaping, just called instead of spliced."

{ lib, mountBin, mountpointBin, mkdir, chown, globalBlocking }:

# Same behavior as the old lib/mount-entry.nix (one file, generated a
# fresh inline bash block per device entry), restructured so the actual
# bash logic is a real, shared, standalone file (./mount-entry.sh)
# instead of being regenerated per entry. `enabled = false` or `at == null`
# still short-circuits entirely in Nix (call = ""), same as before --
# nothing to do at activation time, no bash emitted at all for an inert
# entry. Otherwise: every value the old version baked into the generated
# bash text via Nix string interpolation (leaf-resolution mode, blocking,
# owner presence, and the escaped uuid/at/key/owner literals themselves)
# is still computed here, still escaped with lib.escapeShellArg exactly
# as before -- just handed to mountpointsMountEntry as call arguments
# instead of being spliced into a one-off block of text.
#
# mount-entry.sh is a real standalone bash file -- @MKDIR_BIN@/
# @MOUNTPOINT_BIN@/@MOUNT_BIN@/@CHOWN_BIN@ are the only dynamic bits
# (absolute tool paths, not PATH lookups -- same convention the old
# version used), substituted in verbatim below.
{
  functions = builtins.replaceStrings
    [ "@MKDIR_BIN@" "@MOUNTPOINT_BIN@" "@MOUNT_BIN@" "@CHOWN_BIN@" ]
    [ mkdir mountpointBin mountBin chown ]
    (builtins.readFile ./mount-entry.sh);

  call =
    key: entry:
    if !entry.enabled || entry.at == null then
      ""
    else
      let
        uuid = entry.uuid;
        at = entry.at;
        asVal = entry.as or null;
        owner = entry.owner or null;
        blocking = if (entry.blocking or null) != null then entry.blocking else globalBlocking;
        dev = "/dev/disk/by-uuid/${uuid}";

        # Same 5-way branch as the old leafExpr -- LABEL/NAME/omitted need
        # a live disk query (mode passed through to mountpointsResolveLeaf
        # at runtime, same as before), UUID/literal are already known here
        # at eval time (mode = "literal", the value itself passed straight
        # through instead of being resolved).
        mode =
          if asVal == null then "auto"
          else if asVal == "LABEL" then "label"
          else if asVal == "NAME" then "name"
          else "literal";
        literalLeaf =
          if asVal == "UUID" then uuid
          else if asVal != null && asVal != "LABEL" && asVal != "NAME" then asVal
          else "";
      in
      lib.concatStringsSep " " [
        "mountpointsMountEntry"
        (lib.escapeShellArg dev)
        (lib.escapeShellArg mode)
        (lib.escapeShellArg literalLeaf)
        (if blocking then "1" else "0")
        (lib.escapeShellArg key)
        (lib.escapeShellArg uuid)
        (lib.escapeShellArg at)
        (if owner != null then "1" else "0")
        (lib.escapeShellArg (if owner != null then owner else ""))
      ];
}
