#!/usr/bin/env bash
# plugins.sh -- generate a ready-to-paste plugin record ({ name = ...; url =
# ...; }) for Nixos/modules/hyprland/plugins/default.nix's
# config.vars.hyprland.hyprlandPlugins list, from just a git URL. No mkPlugin
# wrapper needed per entry -- that function (in ./plugins.nix) is mapped
# over the whole list once.
#
# Prints a colored, spinner-driven progress trail on stderr while it works,
# and exactly one thing on stdout: the finished block, plain, no color --
# meant to be piped/copy-pasted straight into the real config. Progress
# output is auto-off when stderr isn't a terminal or $NO_COLOR is set, same
# convention as `pacnix modules`.
#
# `name` is never guessed: it's read straight out of the plugin's own
# CMakeLists.txt/meson.build (add_library/shared_library/shared_module,
# including resolving meson.project_name() back to its literal string) --
# the same name its build will actually produce as a .so.
#
# Build system (cmake vs meson) is detected from what's actually in the
# repo, not assumed -- mkPlugin's nativeBuildInputs default is cmake, but a
# meson-based plugin gets meson+ninja instead.
#
# Missing pkg-config deps: a missing module gets a few deterministic name
# transforms tried against nixpkgs (dots/dashes -> underscores, strip a
# trailing version number) -- each is a single, instant attribute-existence
# check, not a scan of nixpkgs. Any candidate that exists gets tried in a
# real rebuild; if the error for that module goes away, it's kept, if not,
# the next candidate is tried. This is not a hardcoded name->package table
# (it's a generic transform, not specific knowledge) and not a nixpkgs-wide
# index (each check is one attribute, not all of them) -- it's how it
# reaches full resolution without either.
#
# If this plugin (same url) already has an entry in the real config, its
# extraBuildInputs/nativeBuildInputs are reused as the starting point, so
# re-running this against something already configured (e.g. bumping its
# rev) succeeds immediately.
#
# If, after all that, a module still can't be resolved (nothing in nixpkgs
# under any tried name actually satisfies it) or the failure isn't a
# missing-dependency problem at all (e.g. the plugin's pinned commit
# doesn't compile against this Hyprland version), it's reported plainly --
# that's a genuine fact about the plugin, not something to paper over.
#
# The trial build is throwaway: `nix build --no-link` creates no GC root,
# so nothing persists because of this script -- the only build that
# actually sticks is the real one home-manager does once you paste the
# block in and rebuild.
#
# Usage: pacnix plugins <git-url> [rev]
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

# --- ui: colors + spinner, informational only -- stdout (the pasteable
# block) never touches any of this.
ui_tty=0
[ -t 2 ] && [ -z "${NO_COLOR:-}" ] && ui_tty=1

if [ "$ui_tty" -eq 1 ]; then
    c_cyan=$'\033[36m'; c_green=$'\033[32m'; c_red=$'\033[31m'
    c_yellow=$'\033[33m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
else
    c_cyan=""; c_green=""; c_red=""; c_yellow=""; c_dim=""; c_reset=""
fi

spinner_pid=""
build_err=""

step_start() {
    local msg="$1"
    if [ "$ui_tty" -eq 1 ]; then
        (
            frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
            i=0
            while :; do
                printf "\r%s%s%s %s%s...%s" \
                    "$c_cyan" "${frames:$((i % ${#frames})):1}" "$c_reset" "$msg" "$c_dim" "$c_reset" >&2
                i=$((i + 1))
                sleep 0.08
            done
        ) &
        spinner_pid=$!
        disown
    else
        echo "$msg..." >&2
    fi
}

step_end() {
    local symbol="$1" color="$2" msg="$3"
    if [ -n "$spinner_pid" ]; then
        kill "$spinner_pid" 2>/dev/null
        wait "$spinner_pid" 2>/dev/null
        spinner_pid=""
    fi
    if [ "$ui_tty" -eq 1 ]; then
        printf "\r\033[K%s%s%s %s\n" "$color" "$symbol" "$c_reset" "$msg" >&2
    else
        echo "$msg" >&2
    fi
}

note() {
    if [ "$ui_tty" -eq 1 ]; then
        printf "  %s%s%s\n" "$c_dim" "$1" "$c_reset" >&2
    else
        echo "  $1" >&2
    fi
}

cleanup() {
    [ -n "$spinner_pid" ] && kill "$spinner_pid" 2>/dev/null
    [ -n "$build_err" ] && rm -f "$build_err"
}
trap cleanup EXIT

url="${1:-}"
rev="${2:-}"

if [ -z "$url" ]; then
    echo "usage: pacnix plugins <git-url> [rev]" >&2
    exit 1
fi

step_start "prefetching $url"
json="$(nix run nixpkgs#nix-prefetch-git -- --url "$url" ${rev:+--rev "$rev"} --quiet 2>/dev/null)"

got_rev="$(grep -oP '"rev"\s*:\s*"\K[^"]+' <<< "$json" || true)"
hash="$(grep -oP '"hash"\s*:\s*"\K[^"]+' <<< "$json" || true)"
commit_date="$(grep -oP '"date"\s*:\s*"\K[^"]+' <<< "$json" | cut -c1-10 || true)"
src_path="$(grep -oP '"path"\s*:\s*"\K[^"]+' <<< "$json" || true)"

if [ -z "$got_rev" ] || [ -z "$hash" ] || [ -z "$src_path" ]; then
    step_end "✗" "$c_red" "failed to prefetch $url -- check the URL/rev"
    exit 1
fi
step_end "✓" "$c_green" "prefetched @ ${got_rev:0:8}"

version="0-unstable-${commit_date:-unknown}"
flake_real="$(readlink -f "$FLAKE")"
plugins_file="$flake_real/Nixos/modules/hyprland/plugins/default.nix"

# Real library name, straight from the build files -- not a guess. Every
# grep here is allowed to legitimately find nothing (that's how the
# fallbacks work), so each is guarded with `|| true` -- otherwise `grep |
# head -1` trips `set -o pipefail` on a plain no-match and silently kills
# the script before the next fallback ever runs.
step_start "reading library name from source"
name="$(grep -rhoP 'add_library\(\s*\K[A-Za-z0-9_.+-]+(?=\s+SHARED)' --include=CMakeLists.txt "$src_path" 2>/dev/null | head -1 || true)"
[ -z "$name" ] && name="$(grep -rhoP 'add_library\(\s*\K[A-Za-z0-9_.+-]+' --include=CMakeLists.txt "$src_path" 2>/dev/null | head -1 || true)"

if [ -z "$name" ]; then
    meson_file="$(grep -rlP '\b(shared_library|shared_module)\(' --include=meson.build "$src_path" 2>/dev/null | head -1 || true)"
    if [ -n "$meson_file" ]; then
        name="$(grep -oP "(shared_library|shared_module)\(\s*'\K[^']+" "$meson_file" | head -1 || true)"
        if [ -z "$name" ] && grep -qP '(shared_library|shared_module)\(\s*meson\.project_name\(\)' "$meson_file"; then
            name="$(grep -oP "project\(\s*'\K[^']+" "$meson_file" | head -1 || true)"
        fi
    fi
fi

if [ -z "$name" ]; then
    step_end "✗" "$c_red" "couldn't find a shared-library target (add_library/shared_library/shared_module)"
    echo "inspect the source and name it by hand:" >&2
    echo "  $src_path" >&2
    exit 1
fi
step_end "✓" "$c_green" "name: $name"

# Reuse extraBuildInputs/nativeBuildInputs already known to work for this
# exact url, if it's already in the real config -- from its own text, not
# re-derived.
step_start "checking existing config for this url"
existing_attrs=()
existing_native=()
if [ -f "$plugins_file" ]; then
    # Records are plain { ... } attrsets in the list (no mkPlugin wrapper),
    # each with its own bare { / } alone on a line -- matches the same
    # convention config/scripts.nix's records use.
    block="$(awk -v u="$url" '
        /^\s*\{\s*$/ { block = ""; capturing = 1 }
        capturing { block = block $0 "\n" }
        /^\s*\}\s*$/ {
            if (capturing && index(block, "url = \"" u "\"") > 0) { print block }
            capturing = 0
        }
    ' "$plugins_file")"
    while IFS= read -r a; do existing_attrs+=("$a"); done < <(
        grep -oP 'extraBuildInputs\s*=\s*\[[^]]*\];' <<< "$block" 2>/dev/null \
            | grep -oP 'pkgs\.\K[A-Za-z0-9_-]+' || true
    )
    while IFS= read -r a; do existing_native+=("$a"); done < <(
        grep -oP 'nativeBuildInputs\s*=\s*\[[^]]*\];' <<< "$block" 2>/dev/null \
            | grep -oP 'pkgs\.\K[A-Za-z0-9_-]+' || true
    )
fi
if [ "${#existing_attrs[@]}" -gt 0 ] || [ "${#existing_native[@]}" -gt 0 ]; then
    step_end "✓" "$c_green" "found an existing entry, reusing its build inputs"
else
    step_end "→" "$c_cyan" "not configured yet"
fi

# Native build inputs: reuse from an existing config entry for this url if
# there is one, else detect from the plugin's own top-level build file --
# mkPlugin's own default is cmake+pkg-config, so only a meson-based plugin
# (meson.build with no CMakeLists.txt) needs anything different.
native_attrs=("${existing_native[@]}")
if [ "${#native_attrs[@]}" -eq 0 ]; then
    if [ -f "$src_path/meson.build" ] && [ ! -f "$src_path/CMakeLists.txt" ]; then
        native_attrs=(meson ninja pkg-config)
    else
        native_attrs=(cmake pkg-config)
    fi
fi
native_list=""
for a in "${native_attrs[@]}"; do native_list+="pkgs.$a "; done
note "build system: ${native_attrs[*]}"

# Plain fact, not a diagnosis -- whatever the build does or doesn't do
# below, this is the Hyprland version it did it against.
hypr_version="$(nix eval --extra-experimental-features "nix-command flakes" \
    "$flake_real#nixosConfigurations.$HOST.pkgs.hyprland.version" --raw 2>/dev/null || true)"
[ -n "$hypr_version" ] && note "hyprland version: $hypr_version"

is_default_native=0
if [ "${#native_attrs[@]}" -eq 2 ] && [ "${native_attrs[0]}" = "cmake" ] && [ "${native_attrs[1]}" = "pkg-config" ]; then
    is_default_native=1
fi

# Candidate nixpkgs attribute names for a missing pkg-config module: a
# handful of generic, content-free string transforms -- no specific
# package knowledge baked in.
candidates_for() {
    local m="$1" c
    local -A seen=()
    for c in \
        "$m" \
        "${m//./_}" \
        "${m//-/_}" \
        "${m%-[0-9]*}" \
        "${m%.[0-9]*}"
    do
        [ -z "$c" ] && continue
        [ -n "${seen[$c]:-}" ] && continue
        seen[$c]=1
        echo "$c"
    done
}

attr_exists() {
    nix eval --extra-experimental-features "nix-command flakes" \
        "$flake_real#nixosConfigurations.$HOST.pkgs.$1" --apply 'x: "ok"' >/dev/null 2>&1
}

build_err="$(mktemp)"

try_build() {
    local extra_list=""
    for a in "${extra_attrs[@]}"; do extra_list+="pkgs.$a "; done
    local build_expr="
let
  pkgs = (builtins.getFlake \"$flake_real\").nixosConfigurations.$HOST.pkgs;
in
pkgs.hyprland.stdenv.mkDerivation {
  pname = \"hyprland-${name}\";
  version = \"${version}\";
  src = pkgs.fetchgit {
    url = \"${url}\";
    rev = \"${got_rev}\";
    hash = \"${hash}\";
  };
  nativeBuildInputs = [ $native_list ];
  buildInputs = [ pkgs.hyprland ] ++ pkgs.hyprland.buildInputs ++ [ $extra_list ];
  dontStrip = true;
}
"
    nix build --impure --no-link --print-out-paths --expr "$build_expr" 2>"$build_err"
}

print_block() {
    printf '\n    {\n      name = "%s";\n      url = "%s";\n      rev = "%s";\n      hash = "%s";\n      version = "%s";\n' \
        "$name" "$url" "$got_rev" "$hash" "$version"
    if [ "$is_default_native" -eq 0 ]; then
        line="      nativeBuildInputs = ["
        for a in "${native_attrs[@]}"; do line+=" pkgs.$a"; done
        line+=" ];"
        echo "$line"
    fi
    if [ "${#extra_attrs[@]}" -gt 0 ]; then
        line="      extraBuildInputs = ["
        for a in "${extra_attrs[@]}"; do line+=" pkgs.$a"; done
        line+=" ];"
        echo "$line"
    fi
    echo "    }"
}

extra_attrs=("${existing_attrs[@]}")
rejected=()
success=0
attempt=0
max_attempts=8
missing=()

while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))

    step_start "building (attempt $attempt)"
    if out_path="$(try_build)"; then
        step_end "✓" "$c_green" "build succeeded"
        success=1
        break
    fi
    step_end "✗" "$c_red" "attempt $attempt failed"

    missing=()
    while IFS= read -r m; do missing+=("$m"); done < <(grep -oP "No package '\K[^']+" "$build_err" | sort -u)
    [ "${#missing[@]}" -eq 0 ] && break

    progress=0
    for m in "${missing[@]}"; do
        note "missing: $m -- searching nixpkgs for a matching attribute"
        while IFS= read -r cand; do
            already=0
            for a in "${extra_attrs[@]}" "${rejected[@]}"; do [ "$a" = "$cand" ] && already=1 && break; done
            [ "$already" -eq 1 ] && continue

            if attr_exists "$cand"; then
                printf "  %s✓%s pkgs.%s exists -- retrying with it\n" "$c_green" "$c_reset" "$cand" >&2
                extra_attrs+=("$cand")
                progress=1
                break
            else
                printf "  %spkgs.%s doesn't exist%s\n" "$c_dim" "$cand" "$c_reset" >&2
                rejected+=("$cand")
            fi
        done < <(candidates_for "$m")
    done

    [ "$progress" -eq 0 ] && break
done

if [ "$success" -eq 1 ]; then
    if [ ! -f "$out_path/lib/lib${name}.so" ]; then
        echo "built, but lib${name}.so isn't where expected under $out_path/lib --" >&2
        echo "inspect it and adjust libFile in the block below:" >&2
    fi
    print_block
else
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "missing pkg-config module(s): ${missing[*]} -- nothing in nixpkgs under the" >&2
        echo "obvious name(s) satisfies them, add the right package to extraBuildInputs" >&2
        echo "below yourself, then rebuild." >&2
    else
        echo "build failed for a reason other than a missing pkg-config module:" >&2
        # The raw log is compiler output -- drop the actual g++/gcc/clang
        # invocation lines (never useful, often 2000+ chars of -I flags) and
        # truncate anything else that's still absurdly long, so the fatal
        # error itself isn't buried under noise.
        grep -avP '^\s*(>\s*)?(g\+\+|gcc|cc|clang(\+\+)?)\s' "$build_err" \
            | awk '{ if (length($0) > 300) print substr($0, 1, 200) " [...]"; else print }' \
            | tail -20 >&2
    fi
    print_block
    exit 1
fi
