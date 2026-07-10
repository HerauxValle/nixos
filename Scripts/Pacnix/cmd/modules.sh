#!/usr/bin/env bash
set -euo pipefail

# Two source sets, selected by -h / -n. Neither given = query both.
#   -h (home-manager)  nix-community/home-manager's modules/programs --
#                       user-level `programs.*` home-manager options
#                       (programs.fresh-editor, programs.fish, ...)
#   -n (nixos)          nixpkgs' nixos/modules/programs -- NixOS
#                       system-level `programs.*` options (programs.steam,
#                       programs.direnv, ...)
#
# Neither set is exhaustive for system options: plenty of real
# `programs.*` NixOS options live outside nixpkgs' own
# nixos/modules/programs/ dir -- either elsewhere in nixpkgs (security/,
# virtualisation/, ...) or shipped entirely by a separate flake
# (programs.hyprland from the hyprland flake, programs.silentSDDM from
# silent-sddm -- see flake.nix). A "not available" result under -n only
# means "not in nixpkgs' own programs/ dir", not "doesn't exist anywhere".

HM_REPO="nix-community/home-manager"
HM_DIR="modules/programs"
HM_RAW_BASE="https://raw.githubusercontent.com/$HM_REPO/master"
NIXOS_REPO="NixOS/nixpkgs"
NIXOS_DIR="nixos/modules/programs"
NIXOS_RAW_BASE="https://raw.githubusercontent.com/$NIXOS_REPO/master"

# Local cache of the two directory listings -- this is the whole reason
# a routine `-q` call used to burn 2 GitHub API requests (one per source)
# every single invocation: nothing was ever kept between runs. That list
# barely changes day to day, so by default this now reads whatever was
# cached last and only ever hits GitHub again when told to with -r.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pacnix/modules"
HM_CACHE="$CACHE_DIR/home-manager.tsv"
NIXOS_CACHE="$CACHE_DIR/nixos.tsv"

# --- color ---
#
# Same 0;31/0;33/0;32/0m red/yellow/green/reset codes as
# Nixos/modules/backup/dotfiles.nix uses, plus cyan/magenta for the [h]/[n]
# source tags and a dim tone for secondary info (sha, urls). Off entirely
# when stdout isn't a terminal (piped/redirected) or $NO_COLOR is set, so
# `pacnix modules -q x | grep y` never has to deal with escape codes.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_H=$'\033[0;36m'      # home-manager tag
    C_N=$'\033[0;35m'      # NixOS system tag
    C_GREEN=$'\033[0;32m'  # available
    C_RED=$'\033[0;31m'    # not available / errors
    C_YELLOW=$'\033[0;33m' # closest-match hints / warnings
    C_DIM=$'\033[0;90m'    # sha, urls
    C_BOLD=$'\033[1m'      # module names
    C_RESET=$'\033[0m'
else
    C_H=""; C_N=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi
color_for_tag() { [ "$1" = "h" ] && echo "$C_H" || echo "$C_N"; }

# --- flag parsing ---
#
# -q, -s, -c, -h, -n, -i, -r can combine in any order in one token (-qs,
# -sq, -qsc, -nq, -hi, -qr, ...) -- each letter just flips a boolean. -q
# additionally needs a search term, which is always its own separate
# argument (never glued into the flag token itself) so "-qs steam" and
# "-sq steam" both work the same.

show_source=0
do_curl=0
have_query=0
use_hm=0
use_nixos=0
show_info=0
refetch=0
query=""

for a in "$@"; do
    case "$a" in
        -*)
            flags="${a#-}"
            if [[ ! "$flags" =~ ^[qschnir]+$ ]]; then
                echo "${C_RED}unknown flag: $a${C_RESET}" >&2
                echo "usage: pacnix modules [-q <term>] [-s] [-c] [-h] [-n] [-i] [-r]" >&2
                exit 1
            fi
            [[ "$flags" == *q* ]] && have_query=1
            [[ "$flags" == *s* ]] && show_source=1
            [[ "$flags" == *c* ]] && do_curl=1
            [[ "$flags" == *h* ]] && use_hm=1
            [[ "$flags" == *n* ]] && use_nixos=1
            [[ "$flags" == *i* ]] && show_info=1
            [[ "$flags" == *r* ]] && refetch=1
            ;;
        *)
            if [ -n "$query" ]; then
                echo "${C_RED}error: unexpected extra argument: $a${C_RESET}" >&2
                exit 1
            fi
            query="$a"
            ;;
    esac
done

# neither -h nor -n given -> query both
if [ "$use_hm" -eq 0 ] && [ "$use_nixos" -eq 0 ]; then
    use_hm=1
    use_nixos=1
fi

if [ "$have_query" -eq 1 ] && [ -z "$query" ]; then
    echo "${C_RED}error: -q needs a search term, e.g. pacnix modules -q steam${C_RESET}" >&2
    exit 1
fi
if [ "$have_query" -eq 0 ] && [ -n "$query" ]; then
    echo "${C_RED}error: '$query' needs -q to search for it, e.g. pacnix modules -q $query${C_RESET}" >&2
    exit 1
fi

# --- fetch a module list: name<TAB>type<TAB>html_url<TAB>path<TAB>tag<TAB>sha,
# sorted alphabetically (case-insensitive). type is "file" (a plain
# <name>.nix module) or "dir" (a module split across multiple files). sha
# is the git blob sha GitHub's directory-listing response already includes
# for free -- used as -i's "(version)" stand-in with no separate request.
# (A "last updated" timestamp would need a separate commits-API call per
# file with no bulk equivalent on unauthenticated REST -- 600+ requests
# just to list them all, so that idea got dropped rather than built.)
# Parsed with python3 rather than jq -- jq isn't installed anywhere in
# this config, python3 already is (installed.nix). tag is "h" or "n",
# fixed per call, so it survives concatenation into one combined table.

fetch_source() {
    local repo="$1" dir="$2" tag="$3"
    curl -sf "https://api.github.com/repos/$repo/contents/$dir" | python3 -c "
import json, sys
data = json.load(sys.stdin)
rows = []
for item in data:
    name = item['name']
    if item['type'] == 'file' and name.endswith('.nix'):
        name = name[:-4]
    rows.append((name, item['type'], item['html_url'], item['path'], item['sha'][:7]))
rows.sort(key=lambda r: r[0].lower())
for name, typ, url, path, sha in rows:
    print(f'{name}\t{typ}\t{url}\t{path}\t$tag\t{sha}')
"
}

# Loads one source's rows from cache, refetching (and rewriting the cache)
# only when -r was given or the cache doesn't exist yet. A missing cache
# without -r is a hard error rather than a silent auto-fetch -- so a
# routine `pacnix modules -q x` never hits GitHub on its own; you opt in
# once with -r and every plain call after that is free.
load_source() {
    local repo="$1" dir="$2" tag="$3" cache="$4" label="$5"
    if [ "$refetch" -eq 1 ] || [ ! -s "$cache" ]; then
        if [ "$refetch" -eq 0 ]; then
            echo "${C_YELLOW}no local cache for $label yet -- rerun with -r to fetch it (e.g. pacnix modules -r)${C_RESET}" >&2
            exit 1
        fi
        local rows
        rows="$(fetch_source "$repo" "$dir" "$tag")" || { echo "${C_RED}error: couldn't reach GitHub's API for $label${C_RESET}" >&2; exit 1; }
        mkdir -p "$CACHE_DIR"
        printf '%s\n' "$rows" > "$cache"
    fi
    cat "$cache"
}

modules=""
if [ "$use_hm" -eq 1 ]; then
    rows="$(load_source "$HM_REPO" "$HM_DIR" "h" "$HM_CACHE" "home-manager")"
    modules="$rows"
fi
if [ "$use_nixos" -eq 1 ]; then
    rows="$(load_source "$NIXOS_REPO" "$NIXOS_DIR" "n" "$NIXOS_CACHE" "NixOS system")"
    modules="${modules:+$modules$'\n'}$rows"
fi
modules="$(printf '%s\n' "$modules" | sort -t $'\t' -k1,1f)"

[ -z "$modules" ] && { echo "${C_RED}error: got an empty module list${C_RESET}" >&2; exit 1; }

# Backed by a real file rather than piped through awk live: an awk pattern
# that `exit`s on its first match (used below to fetch just one row) closes
# its stdin early, and once the combined home-manager+nixos list got big
# enough to exceed the ~64KB pipe buffer, that early close SIGPIPEd the
# still-writing `printf` on the other end of the pipe -- pipefail turned
# that into a silent, unexplained exit. A real file has no such writer to
# kill; awk just stops reading it.
modules_file="$(mktemp)"
trap 'rm -f "$modules_file"' EXIT
printf '%s\n' "$modules" > "$modules_file"

names_for_tag() { awk -F'\t' -v t="$1" '$5==t{print $1}' "$modules_file"; }
row_for() { awk -F'\t' -v n="$1" -v t="$2" '$1==n && $5==t{print; exit}' "$modules_file"; }
label_for_tag() { [ "$1" = "h" ] && echo "home-manager" || echo "NixOS system"; }
raw_base_for_tag() { [ "$1" = "h" ] && echo "$HM_RAW_BASE" || echo "$NIXOS_RAW_BASE"; }

# --- fuzzy match, within one source's namespace -- same family of passes
# as Scripts/Run/run.sh's _search (exact -> substring -> Levenshtein +
# character overlap), minus run.sh's frequency/recency weighting (no usage
# history for a static upstream module list) and minus its middle "fuzzy
# subsequence" pass: that pass has no distance/length gate at all, and
# against real module names it confidently matched nonsense (query "steam"
# -> "streamlink", purely because s-t-e-a-m appears in order somewhere
# inside it) -- worse than just falling through to the scored, thresholded
# Levenshtein pass below. Prints ranked candidates, best first. Reads
# modules_file directly (see the SIGPIPE note above) instead of piping a
# captured $names string through awk.

fuzzy_match() {
    local tag="$1" q="$2" ql
    ql="$(echo "$q" | tr '[:upper:]' '[:lower:]')"

    local exact
    exact="$(awk -F'\t' -v t="$tag" -v ql="$ql" '$5==t && tolower($1)==ql{print $1; exit}' "$modules_file")"
    if [ -n "$exact" ]; then printf '%s\n' "$exact"; return; fi

    local sub
    sub="$(awk -F'\t' -v t="$tag" -v ql="$ql" '$5==t && tolower($1) ~ ql {print length($1)"|"$1}' "$modules_file" | sort -n | cut -d'|' -f2-)"
    if [ -n "$sub" ]; then printf '%s\n' "$sub"; return; fi

    awk -F'\t' -v t="$tag" -v ql="$ql" '
        function lower(s){return tolower(s)}
        function levenshtein(s,t,   sl,tl,i,j,prev,curr,tmp){sl=length(s);tl=length(t);if(!sl)return tl;if(!tl)return sl;for(j=0;j<=tl;j++)prev[j]=j;for(i=1;i<=sl;i++){curr[0]=i;for(j=1;j<=tl;j++){if(substr(s,i,1)==substr(t,j,1))curr[j]=prev[j-1];else{tmp=prev[j-1];if(prev[j]<tmp)tmp=prev[j];if(curr[j-1]<tmp)tmp=curr[j-1];curr[j]=tmp+1}};for(j=0;j<=tl;j++)prev[j]=curr[j]};return prev[tl]}
        function charoverlap(a,b,   i,mtch,ch){delete ca;delete cb;for(i=1;i<=length(a);i++)ca[substr(a,i,1)]++;for(i=1;i<=length(b);i++)cb[substr(b,i,1)]++;mtch=0;for(ch in ca)if(ch in cb)mtch+=(ca[ch]<cb[ch]?ca[ch]:cb[ch]);return mtch}
        $5==t {
            tok=lower($1)
            dist=levenshtein(ql,tok)
            maxl=(length(ql)>length(tok)?length(ql):length(tok))
            if (!maxl) next
            sim=1-dist/maxl
            overlap=charoverlap(ql,tok)/length(ql)
            score=sim*0.6+overlap*0.4
            if (score>=0.45) printf "%06.4f|%s\n", score, $1
        }
    ' "$modules_file" | sort -t'|' -k1,1rn | cut -d'|' -f2-
}

curl_module() {
    local tag="$1" type="$2" path="$3" url="$4" raw
    raw="$(raw_base_for_tag "$tag")"
    if [ "$type" = "dir" ]; then
        curl -sf "$raw/$path/default.nix" || echo "${C_YELLOW}# (directory module, couldn't guess the file -- see $url)${C_RESET}"
    else
        curl -sf "$raw/$path" || echo "${C_RED}# (failed to fetch)${C_RESET}"
    fi
}

# format one row for display: plain "name", "name - url" (-s), or with -i
# "[tag] - name (sha)" -- sha is the blob sha already sitting in the row
# (see fetch_source), not a separate request. (+ " - url" if -s is also
# set). Takes fields as separate args (not a joined row string) so callers
# that already have them split -- both call sites do -- don't need to
# re-join and re-split them.
format_line() {
    local name="$1" type="$2" url="$3" path="$4" tag="$5" sha="$6" tagcolor
    local line
    if [ "$show_info" -eq 1 ]; then
        tagcolor="$(color_for_tag "$tag")"
        line="${tagcolor}[$tag]${C_RESET} - ${C_BOLD}${name}${C_RESET} ${C_DIM}($sha)${C_RESET}"
    else
        line="${C_BOLD}${name}${C_RESET}"
    fi
    [ "$show_source" -eq 1 ] && line="$line ${C_DIM}- $url${C_RESET}"
    printf '%s\n' "$line"
}

# --- -q: single-module query, once per active source ---

if [ "$have_query" -eq 1 ]; then
    for tag in h n; do
        { [ "$tag" = "h" ] && [ "$use_hm" -eq 0 ]; } && continue
        { [ "$tag" = "n" ] && [ "$use_nixos" -eq 0 ]; } && continue
        label="$(label_for_tag "$tag")"

        candidates="$(fuzzy_match "$tag" "$query")"
        if [ -z "$candidates" ]; then
            echo "${C_RED}not available${C_RESET} in $label: $query"
            [ "$tag" = "n" ] && echo "${C_YELLOW}(nixos/modules/programs/ only -- could still exist elsewhere in nixpkgs, or come from a separate flake)${C_RESET}" >&2
            continue
        fi

        match="$(printf '%s\n' "$candidates" | head -1)"
        ql="$(echo "$query" | tr '[:upper:]' '[:lower:]')"
        matchl="$(echo "$match" | tr '[:upper:]' '[:lower:]')"
        row="$(row_for "$match" "$tag")"
        IFS=$'\t' read -r rname rtype rurl rpath rtag rsha <<< "$row"

        if [ "$show_info" -eq 1 ]; then
            prefix=""
        else
            prefix="${C_GREEN}available${C_RESET} in $label: "
        fi
        line="$prefix$(format_line "$rname" "$rtype" "$rurl" "$rpath" "$rtag" "$rsha")"
        [ "$matchl" != "$ql" ] && line="$line ${C_YELLOW}(closest match for '$query')${C_RESET}"
        echo "$line"

        alts="$(printf '%s\n' "$candidates" | tail -n +2 | head -3)"
        [ -n "$alts" ] && echo "${C_YELLOW}also close${C_RESET} ($label): $(printf '%s, ' $alts | sed 's/, $//')"

        if [ "$do_curl" -eq 1 ]; then
            curl_module "$rtag" "$rtype" "$rpath" "$rurl"
        fi
    done
    exit 0
fi

# --- no -q: listing / bulk mode ---

total=$(printf '%s\n' "$modules" | wc -l)

# -i costs nothing extra (sha is already in $modules), so only -c's actual
# file-content fetches warrant a heads-up here.
if [ "$do_curl" -eq 1 ]; then
    echo "${C_YELLOW}about to fetch and print the raw source of all $total modules -- that's $total requests and a lot of terminal output.${C_RESET}" >&2
    read -r -p "continue? [y/N] " reply
    case "$reply" in
        y | Y | yes | YES) ;;
        *) echo "${C_RED}aborted.${C_RESET}" >&2; exit 1 ;;
    esac
fi

while IFS=$'\t' read -r name type url path tag sha; do
    format_line "$name" "$type" "$url" "$path" "$tag" "$sha"
    if [ "$do_curl" -eq 1 ]; then
        curl_module "$tag" "$type" "$path" "$url"
        echo
    fi
done <<< "$modules"
