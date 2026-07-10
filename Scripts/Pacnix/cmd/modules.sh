#!/usr/bin/env bash
set -euo pipefail

API_URL="https://api.github.com/repos/nix-community/home-manager/contents/modules/programs"
RAW_BASE="https://raw.githubusercontent.com/nix-community/home-manager/master/modules/programs"

# --- flag parsing ---
#
# -q, -s, -c can combine in any order in one token (-qs, -sq, -qsc, ...) --
# each letter just flips a boolean. -q additionally needs a search term,
# which is always its own separate argument (never glued into the flag
# token itself) so "-qs steam" and "-sq steam" both work the same.

show_source=0
do_curl=0
have_query=0
query=""

for a in "$@"; do
    case "$a" in
        -*)
            flags="${a#-}"
            if [[ ! "$flags" =~ ^[qsc]+$ ]]; then
                echo "unknown flag: $a" >&2
                echo "usage: pacnix modules [-q <term>] [-s] [-c]" >&2
                exit 1
            fi
            [[ "$flags" == *q* ]] && have_query=1
            [[ "$flags" == *s* ]] && show_source=1
            [[ "$flags" == *c* ]] && do_curl=1
            ;;
        *)
            if [ -n "$query" ]; then
                echo "error: unexpected extra argument: $a" >&2
                exit 1
            fi
            query="$a"
            ;;
    esac
done

if [ "$have_query" -eq 1 ] && [ -z "$query" ]; then
    echo "error: -q needs a search term, e.g. pacnix modules -q steam" >&2
    exit 1
fi
if [ "$have_query" -eq 0 ] && [ -n "$query" ]; then
    echo "error: '$query' needs -q to search for it, e.g. pacnix modules -q $query" >&2
    exit 1
fi

# --- fetch the module list: name<TAB>type<TAB>html_url, one per line,
# sorted alphabetically (case-insensitive). type is "file" (a plain
# <name>.nix module) or "dir" (a module split across multiple files under
# modules/programs/<name>/). Parsed with python3 rather than jq -- jq isn't
# installed anywhere in this config, python3 already is (installed.nix).

modules="$(curl -sf "$API_URL" | python3 -c '
import json, sys
data = json.load(sys.stdin)
rows = []
for item in data:
    name = item["name"]
    if item["type"] == "file" and name.endswith(".nix"):
        name = name[:-4]
    rows.append((name, item["type"], item["html_url"]))
rows.sort(key=lambda r: r[0].lower())
for name, typ, url in rows:
    print(f"{name}\t{typ}\t{url}")
')" || { echo "error: couldn't reach GitHub's API ($API_URL)" >&2; exit 1; }

[ -z "$modules" ] && { echo "error: got an empty module list from GitHub" >&2; exit 1; }

names=()
while IFS=$'\t' read -r name _ _; do
    names+=("$name")
done <<< "$modules"

url_for() { printf '%s\n' "$modules" | awk -F'\t' -v n="$1" '$1==n{print $3; exit}'; }
type_for() { printf '%s\n' "$modules" | awk -F'\t' -v n="$1" '$1==n{print $2; exit}'; }

# --- fuzzy match -- same family of passes as Scripts/Run/run.sh's _search
# (exact -> substring -> Levenshtein + character overlap), minus run.sh's
# frequency/recency weighting (no usage history for a static upstream
# module list) and minus its middle "fuzzy subsequence" pass: that pass has
# no distance/length gate at all, and against ~400 real module names it
# confidently matched nonsense (query "steam" -> "streamlink", purely
# because s-t-e-a-m appears in order somewhere inside it) -- worse than
# just falling through to the scored, thresholded Levenshtein pass below.
# Prints ranked candidates, best first; caller takes the first as the
# match and the rest as "did you mean" suggestions.

fuzzy_match() {
    local q="$1" ql
    ql="$(echo "$q" | tr '[:upper:]' '[:lower:]')"

    local exact
    exact="$(printf '%s\n' "${names[@]}" | awk -v ql="$ql" 'tolower($0)==ql{print; exit}')"
    if [ -n "$exact" ]; then printf '%s\n' "$exact"; return; fi

    local sub
    sub="$(printf '%s\n' "${names[@]}" | awk -v ql="$ql" 'tolower($0) ~ ql {print length($0)"|"$0}' | sort -n | cut -d'|' -f2-)"
    if [ -n "$sub" ]; then printf '%s\n' "$sub"; return; fi

    printf '%s\n' "${names[@]}" | awk -v ql="$ql" '
        function lower(s){return tolower(s)}
        function levenshtein(s,t,   sl,tl,i,j,prev,curr,tmp){sl=length(s);tl=length(t);if(!sl)return tl;if(!tl)return sl;for(j=0;j<=tl;j++)prev[j]=j;for(i=1;i<=sl;i++){curr[0]=i;for(j=1;j<=tl;j++){if(substr(s,i,1)==substr(t,j,1))curr[j]=prev[j-1];else{tmp=prev[j-1];if(prev[j]<tmp)tmp=prev[j];if(curr[j-1]<tmp)tmp=curr[j-1];curr[j]=tmp+1}};for(j=0;j<=tl;j++)prev[j]=curr[j]};return prev[tl]}
        function charoverlap(a,b,   i,mtch,ch){delete ca;delete cb;for(i=1;i<=length(a);i++)ca[substr(a,i,1)]++;for(i=1;i<=length(b);i++)cb[substr(b,i,1)]++;mtch=0;for(ch in ca)if(ch in cb)mtch+=(ca[ch]<cb[ch]?ca[ch]:cb[ch]);return mtch}
        {
            tok=lower($0)
            dist=levenshtein(ql,tok)
            maxl=(length(ql)>length(tok)?length(ql):length(tok))
            if (!maxl) next
            sim=1-dist/maxl
            overlap=charoverlap(ql,tok)/length(ql)
            score=sim*0.6+overlap*0.4
            if (score>=0.45) printf "%06.4f|%s\n", score, $0
        }
    ' | sort -t'|' -k1,1rn | cut -d'|' -f2-
}

curl_module() {
    local name="$1" type
    type="$(type_for "$name")"
    if [ "$type" = "dir" ]; then
        curl -sf "$RAW_BASE/$name/default.nix" || {
            echo "# (directory module, couldn't guess the file -- see $(url_for "$name"))"
            return 1
        }
    else
        curl -sf "$RAW_BASE/$name.nix" || echo "# (failed to fetch)"
    fi
}

# --- -q: single-module query ---

if [ "$have_query" -eq 1 ]; then
    candidates="$(fuzzy_match "$query")"
    if [ -z "$candidates" ]; then
        echo "not available: $query"
        exit 0
    fi

    match="$(printf '%s\n' "$candidates" | head -1)"
    ql="$(echo "$query" | tr '[:upper:]' '[:lower:]')"
    matchl="$(echo "$match" | tr '[:upper:]' '[:lower:]')"

    line="available: $match"
    [ "$matchl" != "$ql" ] && line="$line (closest match for '$query')"
    if [ "$show_source" -eq 1 ]; then
        line="$line - $(url_for "$match")"
    fi
    echo "$line"

    alts="$(printf '%s\n' "$candidates" | tail -n +2 | head -3)"
    [ -n "$alts" ] && echo "also close: $(printf '%s, ' $alts | sed 's/, $//')"

    if [ "$do_curl" -eq 1 ]; then
        curl_module "$match"
    fi
    exit 0
fi

# --- no -q: listing / bulk mode ---

if [ "$do_curl" -eq 1 ]; then
    echo "about to fetch and print the raw source of all ${#names[@]} modules -- that's ${#names[@]} requests and a lot of terminal output." >&2
    read -r -p "continue? [y/N] " reply
    case "$reply" in
        y | Y | yes | YES) ;;
        *) echo "aborted." >&2; exit 1 ;;
    esac
    while IFS=$'\t' read -r name _ url; do
        if [ "$show_source" -eq 1 ]; then
            echo "# --- $name - $url ---"
        else
            echo "# --- $name ---"
        fi
        curl_module "$name"
        echo
    done <<< "$modules"
    exit 0
fi

if [ "$show_source" -eq 1 ]; then
    while IFS=$'\t' read -r name _ url; do
        echo "$name - $url"
    done <<< "$modules"
else
    printf '%s\n' "${names[@]}"
fi
