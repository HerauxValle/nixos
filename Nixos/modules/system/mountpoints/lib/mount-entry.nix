{ lib, mountBin, mountpointBin, mkdir, chown, globalBlocking }:

# One mountpoint entry's activation-time bash. `at == null` means this
# entry is a pure registry record (see ./device-type.nix) -- nothing to
# do at activation time, so this returns "" and generates no bash at all.
# Otherwise: warn if the UUID isn't currently attached, resolve `leaf`
# (either a literal already known at eval time, or via
# mountpointsResolveLeaf from ./resolve-leaf.nix for the live-LABEL/NAME
# cases), mkdir the target, mount if not already mounted, then chown if
# `owner` is set (self-healing every activation, mounted-just-now or
# already). A failure (UUID absent, unresolvable leaf, or the mount
# itself failing) either just warns (yellow) or aborts activation (red +
# sets $mountpointsFailed) depending on this entry's own `blocking`,
# falling back to the global default when unset.

key: entry:

if entry.at == null then
  ""
else

let
  uuid = entry.uuid;
  at = entry.at;
  asVal = entry.as or null;
  owner = entry.owner or null;
  blocking = if (entry.blocking or null) != null then entry.blocking else globalBlocking;
  dev = "/dev/disk/by-uuid/${uuid}";

  leafExpr =
    if asVal == null then ''"$(mountpointsResolveLeaf ${lib.escapeShellArg dev} auto)"''
    else if asVal == "LABEL" then ''"$(mountpointsResolveLeaf ${lib.escapeShellArg dev} label)"''
    else if asVal == "NAME" then ''"$(mountpointsResolveLeaf ${lib.escapeShellArg dev} name)"''
    else if asVal == "UUID" then lib.escapeShellArg uuid
    else lib.escapeShellArg asVal;

  # fmt is a printf format string (may contain %s), args are bash
  # expressions substituted into those %s slots -- kept as separate
  # printf arguments, never spliced into the single-quoted format string
  # itself, so runtime values like $target actually expand instead of
  # printing as literal text. Yellow + no marker when non-blocking, red +
  # $mountpointsFailed=1 when blocking.
  warn = fmt: args:
    let argsStr = lib.concatStringsSep " " args; in
    if blocking then
      ''
        printf '\033[0;31merror: modules/system/mountpoints: device.${key}: ${fmt}\033[0m\n' ${argsStr} >&2
        mountpointsFailed=1
      ''
    else
      ''printf '\033[0;33mwarning: modules/system/mountpoints: device.${key}: ${fmt}\033[0m\n' ${argsStr} >&2'';

  chownStep = lib.optionalString (owner != null) ''
        if ${mountpointBin} -q "$target"; then
          ${chown} -- ${lib.escapeShellArg owner} "$target"
        fi
  '';
in

''
  dev=${lib.escapeShellArg dev}
  if [ ! -e "$dev" ]; then
    ${warn "UUID ${uuid} (-> ${at}) not found -- disk likely not attached, mount skipped for now." [ ]}
  else
    leaf=${leafExpr}
    if [ -z "$leaf" ]; then
      ${warn "UUID ${uuid} -- could not resolve a name (no label?) under ${at}, mount skipped for now." [ ]}
    else
      target=${lib.escapeShellArg at}/"$leaf"
      ${mkdir} -p "$target"
      if ! ${mountpointBin} -q "$target"; then
        if ! ${mountBin} "$dev" "$target"; then
          ${warn "failed to mount UUID ${uuid} at \"%s\"." [ ''"$target"'' ]}
        fi
      fi
${chownStep}
    fi
  fi
''
