
{ lib }:

# The submodule type behind config.vars.system.mountpoints.device.<key> -- a
# submodule (not the loose `attrs` this repo otherwise uses for list-of
# options like vars.scripts) specifically so `path` below can be a real
# derived field computed from this same entry's own sibling options,
# giving dot-path access like config.vars.system.mountpoints.device.storage.path
# elsewhere in the repo.

lib.types.submodule ({ config, ... }: {
  options = {
    uuid = lib.mkOption {
      type = lib.types.str;
      description = "Filesystem UUID -- see `lsblk -o NAME,MOUNTPOINTS,UUID,LABEL`.";
    };

    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        false -- this entry is treated as if it doesn't exist at all
        (same as `at` being unset, but without having to actually remove
        `at`/`as`/`owner`/`blocking` to disable it -- flip this back to
        re-enable with everything else intact).
      '';
    };

    at = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Parent directory to mount under. Omitted -- this entry is a pure
        registry record (uuid known, alias key usable elsewhere) with
        nothing actually mounted; `as`/`owner`/`blocking` are ignored in
        that case.
      '';
    };

    as = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The mount target is `''${at}/''${leaf}`. `leaf` is:
        - omitted: the disk's filesystem LABEL, or its device NAME (e.g.
          "sdd1") if it has no label.
        - "LABEL" / "NAME" / "UUID" (exact keyword): force that specific
          attribute instead of the auto fallback above.
        - any other string: used literally as `leaf`.
        Ignored entirely if `at` is null.
      '';
    };

    owner = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Passed straight through to `chown` against the mount target
        (e.g. "herauxvalle:users" or "1000:100") every activation --
        self-healing if something else changed it. Omitted means
        untouched. Ignored entirely if `at` is null.
      '';
    };

    blocking = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = ''
        Whether a failure on this entry (UUID absent, unresolvable
        leaf, or the mount itself failing) aborts activation instead of
        just printing a warning. null (default) inherits
        config.vars.system.mountpoints.blocking; set true/false to override
        per-entry. Ignored entirely if `at` is null.
      '';
    };

    path = lib.mkOption {
      type = lib.types.str;
      description = ''
        Derived final mount path -- only available when `enabled` is
        true, `at` is set, and `as` is a literal string or "UUID"
        (LABEL/NAME/omitted need a live disk query, only resolvable at
        activation time, so no static path exists to hand back here).
        Accessing this on an entry that doesn't qualify throws, lazily
        -- only entries actually referenced elsewhere in the repo need
        to satisfy this.
      '';
      default =
        if !config.enabled then
          throw "config.vars.system.mountpoints.device.<key>.path: this entry is disabled (enabled = false) -- nothing is mounted, so there's no path."
        else if config.at == null then
          throw "config.vars.system.mountpoints.device.<key>.path: no `at` set on this entry -- nothing is actually mounted, so there's no path."
        else if config.as == null || config.as == "LABEL" || config.as == "NAME" then
          throw "config.vars.system.mountpoints.device.<key>.path: `as` must be a literal string or \"UUID\" for a static path -- LABEL/NAME/omitted need a live disk query."
        else if config.as == "UUID" then
          "${config.at}/${config.uuid}"
        else
          "${config.at}/${config.as}";
    };
  };
})
