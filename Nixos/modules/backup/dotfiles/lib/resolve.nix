{ config, lib, cfg }:

# redactValues'/replaceValues' own key/find/replaceWith resolution, plus
# the excludeHash that gates a history rescrub -- pure Nix, no bash. Real
# commands/scripts live in ./default.nix and ./scripts/ instead.
let
  # redactValues' `key` resolved to an actual value once, here -- every
  # call site below (per-activation redaction, history scrub, GH013
  # recovery) reuses this instead of re-resolving. Tolerant (tryEval), not
  # a hard throw: a redacted value's own key can become unresolvable in
  # exactly the situation this module creates -- the published copy still
  # ships this same resolution logic, and if the ONLY definition of that
  # key was the very line a PREVIOUS redaction pass commented out, whoever
  # evaluates the published copy hits an immediate crash trying to
  # re-resolve it. Confirmed live: this is exactly what broke
  # networking.interfaces.enp3s0.macAddress here before this became
  # tolerant. A failed resolution now just drops that one entry (reported
  # in the runtime warning block below) instead of taking the whole build
  # down with it.
  redactValueResolutions = map
    (r: {
      inherit (r) file key line;
      result = builtins.tryEval (toString (lib.attrByPath (lib.splitString "." r.key) (throw "unresolved") config));
    })
    cfg.redactValues;
  resolvedRedactValues = map (r: { inherit (r) file line; value = r.result.value; })
    (builtins.filter (r: r.result.success) redactValueResolutions);

  # Same idea for replaceValues' `key` variant -- `find` is either typed
  # out literally, or resolved from `key` the same tolerant way as above.
  # An entry that fails to resolve is dropped from every list below (never
  # applied, never hashed, never fed to git-filter-repo) instead of
  # crashing eval -- see default.nix's replaceValues description for why a
  # stale/renamed key has to be tolerated here.
  replaceValueResolutions = map
    (r:
      if r.key != null then
        {
          inherit (r) file replaceWith key line;
          result = builtins.tryEval (toString (lib.attrByPath (lib.splitString "." r.key) (throw "unresolved") config));
        }
      else
        { inherit (r) file replaceWith line; key = null; result = { success = true; value = r.find; }; }
    )
    cfg.replaceValues;
  resolvedReplaceValues = map (r: { inherit (r) file replaceWith line; find = r.result.value; })
    (builtins.filter (r: r.result.success) replaceValueResolutions);

  # Stringifies an entry's optional `line` (null | int | [int...]) for the
  # hash below -- sorted first so [12 33] and [33 12] hash identically,
  # same reasoning as sorting each list itself.
  lineToStr = l:
    if l == null then ""
    else if builtins.isList l then lib.concatMapStringsSep "," toString (lib.sort (a: b: a < b) l)
    else toString l;

  # Pure function of excludeFiles + redactValues + replaceValues' own
  # content (values included, not just which keys/pairs are listed --
  # rotating a redacted value, editing a replaceValues entry, or
  # scoping/unscoping either one with `line` must also trigger a rescrub
  # even though the file didn't change). Sorted first so reordering any
  # list alone doesn't trigger a scrub for nothing.
  excludeHash = builtins.hashString "sha256" (lib.concatStringsSep "\n" (
    (lib.sort (a: b: a < b) cfg.excludeFiles)
    ++ (lib.sort (a: b: a < b) (map (r: "${r.file}\t${r.value}\t${lineToStr r.line}") resolvedRedactValues))
    ++ (lib.sort (a: b: a < b) (map (r: "${r.file}\t${r.find}\t${r.replaceWith}\t${lineToStr r.line}") resolvedReplaceValues))
  ));
in
{
  inherit redactValueResolutions resolvedRedactValues;
  inherit replaceValueResolutions resolvedReplaceValues;
  inherit excludeHash;
}
