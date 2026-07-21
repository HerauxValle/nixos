#!/usr/bin/env bash
FLAKE="/etc/nixos"
HOST="herauxvalle"

# Splits a flake's nixosConfigurations attribute names into the real
# installed-system one and the live-ISO one (nixosConfigurations.
# <name>-iso, see flake.nix) -- used by cmd/published.sh and
# cmd/release.sh, both of which resolve this against a repo checkout
# that isn't necessarily $FLAKE (a temp clone of the published copy,
# where Nixos/config/github/replacements.nix has renamed both
# attributes to placeholders). Prints two lines: the non-iso attr, then
# the iso attr (empty line if none found). Errors if more than one
# non-iso attribute exists.
resolve_flake_attrs() {
    local repoDir="$1"
    local names attr="" isoAttr="" n
    mapfile -t names < <(
        nix eval --json "$repoDir#nixosConfigurations" --apply builtins.attrNames --no-write-lock-file \
            | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)))'
    )
    for n in "${names[@]}"; do
        if [[ "$n" == *-iso ]]; then
            isoAttr="$n"
        else
            if [ -n "$attr" ]; then
                echo "resolve_flake_attrs: more than one non-iso nixosConfigurations attribute found ($attr, $n)." >&2
                return 1
            fi
            attr="$n"
        fi
    done
    if [ -z "$attr" ]; then
        echo "resolve_flake_attrs: no non-iso nixosConfigurations attribute found." >&2
        return 1
    fi
    printf '%s\n%s\n' "$attr" "$isoAttr"
}
