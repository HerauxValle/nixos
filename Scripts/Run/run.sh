#!/usr/bin/env bash

# DB format: path|score|last_access_epoch
DB="${XDG_DATA_HOME:-$HOME/.local/share}/lookup/db"
ALIASDB="${XDG_DATA_HOME:-$HOME/.local/share}/lookup/aliases"
LOG="/tmp/lup.log"
DEFAULT_BG=1  # 1=background, 0=foreground
mkdir -p "$(dirname "$DB")"
touch "$DB" "$LOG" "$ALIASDB"

_bump() {
    local path="$1" now tmp old_score new_score elapsed
    now=$(date +%s)
    read -r old_score last < <(awk -F'|' -v p="$path" '$1==p{print $2, $3}' "$DB")
    if [ -n "$old_score" ]; then
        elapsed=$(( now - last ))
        new_score=$(awk -v s="$old_score" -v t="$elapsed" 'BEGIN{printf "%.4f", s * 0.5^(t/86400) + 1}')
    else
        new_score="1.0000"
    fi
    tmp=$(mktemp)
    awk -F'|' -v p="$path" '$1!=p' "$DB" > "$tmp"
    printf '%s|%s|%d\n' "$path" "$new_score" "$now" >> "$tmp"
    mv "$tmp" "$DB"
}

_log() {
    local pid="$1" cmd="$2" time
    time=$(date '+%H:%M:%S')
    printf '[%s] - [%s] - %s\n' "$time" "$pid" "$cmd" >> "$LOG"
    # keep last 100
    tmp=$(mktemp)
    tail -n 100 "$LOG" > "$tmp" && mv "$tmp" "$LOG"
}

[ -z "$1" ] && { echo "usage: run [-b|-f|-i] [-l [n]] [program] <path|query>" >&2; exit 1; }
[ "$1" = "-h" ] || [ "$1" = "--help" ] && {
    cat >&2 <<'EOF'
usage: run [flags] [program] <path|query>

flags:
  -b            run in background (default)
  -f            run in foreground
  -i            interactive: pick result with fzf
  -q            quit terminal after launch
  -l [n]        show last n launch log entries (default: all)
  -a add [prog] <query|path> <alias>   save alias
  -a rem <alias>                       remove alias
  -a list                              list aliases
  -h, --help    show this help
EOF
    exit 0
}

# -a flag: alias management
if [ "$1" = "-a" ]; then
    subcmd="$2"; shift 2
    case "$subcmd" in
        list)
            [ ! -s "$ALIASDB" ] && { echo "no aliases"; exit 0; }
            awk -F'|' '{
                if ($3) printf "%-16s --> %s  [%s]\n", $1, $2, $3
                else    printf "%-16s --> %s\n", $1, $2
            }' "$ALIASDB"
            ;;
        rem)
            alias="$1"
            tmp=$(mktemp)
            awk -F'|' -v a="$alias" '$1!=a' "$ALIASDB" > "$tmp" && mv "$tmp" "$ALIASDB"
            echo "removed alias: $alias"
            ;;
        add)
            [ $# -lt 2 ] && { echo "usage: run -a add [program] <query> <alias>" >&2; exit 1; }
            args=("$@")
            # last arg is always the alias name
            alias_name="${args[-1]}"
            left=("${args[@]:0:${#args[@]}-1}")

            # detect optional program as first arg if it's a command
            alias_prog=""
            if [ "${#left[@]}" -gt 1 ] && command -v "${left[0]}" &>/dev/null && [ ! -e "${left[0]}" ]; then
                alias_prog="${left[0]}"
                left=("${left[@]:1}")
            fi
            query="${left[*]}"

            # resolve path
            if [ -e "$query" ]; then
                resolved=$(realpath -- "$query")
            else
                resolved=$(bash "$0" -f -p "$query" 2>/dev/null)
                [ -z "$resolved" ] && { echo "could not resolve: $query" >&2; exit 1; }
            fi

            # store alias|path|program
            tmp=$(mktemp)
            awk -F'|' -v a="$alias_name" '$1!=a' "$ALIASDB" > "$tmp"
            printf '%s|%s|%s\n' "$alias_name" "$resolved" "$alias_prog" >> "$tmp"
            mv "$tmp" "$ALIASDB"
            _bump "$resolved"
            echo "alias '$alias_name' --> $resolved${alias_prog:+  [$alias_prog]}"
            ;;
        *) echo "usage: run -a add|rem|list" >&2; exit 1 ;;
    esac
    exit 0
fi

# -l flag: print log and exit
if [ "$1" = "-l" ]; then
    if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
        tail -n "$2" "$LOG"
    else
        cat "$LOG"
    fi
    exit 0
fi

# flags
bg=$DEFAULT_BG
interactive=0
portal=0
quit_terminal=0
[ "$1" = "-b" ] && { bg=1; shift; }
[ "$1" = "-f" ] && { bg=0; shift; }
[ "$1" = "-i" ] && { interactive=1; shift; }
[ "$1" = "-p" ] && { portal=1; shift; }
[ "$1" = "-q" ] && { quit_terminal=1; bg=1; shift; }

if [ "$interactive" -eq 1 ] && ! command -v fzf &>/dev/null; then
    echo "error: -i needs fzf, which isn't installed" >&2
    echo "  install it, then retry" >&2
    exit 1
fi

[ -z "$1" ] && { echo "usage: run [-b] [program [args...]] <path|query>" >&2; exit 1; }

# collect program only if there are more args after it
prog=()
if [ $# -gt 1 ] && command -v "$1" &>/dev/null && [ ! -e "$1" ]; then
    prog=("$1"); shift
fi

arg="$*"  # join remaining args -- handles spaces in paths

# _search <db> <ql> <now> -- runs all 4 passes, returns newline-separated paths
_search() {
    local sdb="$1" ql="$2" now="$3" result=""

    result=$(awk -F'|' -v now="$now" -v ql="$ql" '
        function lower(s) { return tolower(s) }
        function capscore(path, q,    i,c,score) {
            score=0; for(i=1;i<=length(q);i++){c=substr(q,i,1);if(index(lower(path),c)>0&&index(path,c)>0)score++} return score}
        lower($1)~ql{freq=$2*1000/(now-$3+1);cap=capscore($1,ql);printf "%015.4f|%03d|%s\n",freq,cap,$1}
    ' "$sdb" | sort -t'|' -k1,1rn -k2,2rn | cut -d'|' -f3-)

    if [ -z "$result" ]; then
        result=$(awk -F'|' -v now="$now" -v ql="$ql" '
            function lower(s){return tolower(s)}
            function basename(p,   n){n=split(p,a,"/");return a[n]}
            function fuzzy(s,q,   i,j){j=1;for(i=1;i<=length(s);i++){if(substr(lower(s),i,1)==substr(q,j,1))j++;if(j>length(q))return 1}return 0}
            fuzzy(basename($1),ql){freq=$2*1000/(now-$3+1);printf "%015.4f|%s\n",freq,$1}
        ' "$sdb" | sort -rn | cut -d'|' -f2-)
    fi

    if [ -z "$result" ]; then
        result=$(awk -F'|' -v now="$now" -v ql="$ql" '
            function lower(s){return tolower(s)}
            function basename(p,   n){n=split(p,a,"/");return a[n]}
            function lcs(a,b,   i,j,best,cur){best=0;for(i=1;i<=length(a);i++){cur=0;for(j=1;j<=length(b);j++){if(substr(a,i,1)==substr(lower(b),j,1)){cur++;i++}else cur=0;if(cur>best)best=cur};i-=cur};return best}
            {base=basename($1);score=lcs(ql,base);if(score>=3){freq=$2*1000/(now-$3+1);printf "%03d|%015.4f|%s\n",score,freq,$1}}
        ' "$sdb" | sort -t'|' -k1,1rn -k2,2rn | cut -d'|' -f3-)
    fi

    if [ -z "$result" ]; then
        result=$(awk -F'|' -v now="$now" -v ql="$ql" '
            function lower(s){return tolower(s)}
            function basename(p,   n){n=split(p,a,"/");return a[n]}
            function levenshtein(s,t,   sl,tl,i,j,prev,curr,tmp){sl=length(s);tl=length(t);if(!sl)return tl;if(!tl)return sl;for(j=0;j<=tl;j++)prev[j]=j;for(i=1;i<=sl;i++){curr[0]=i;for(j=1;j<=tl;j++){if(substr(s,i,1)==substr(t,j,1))curr[j]=prev[j-1];else{tmp=prev[j-1];if(prev[j]<tmp)tmp=prev[j];if(curr[j-1]<tmp)tmp=curr[j-1];curr[j]=tmp+1}};for(j=0;j<=tl;j++)prev[j]=curr[j]};return prev[tl]}
            function charoverlap(a,b,   i,mtch,ch){delete _ca;delete _cb;for(i=1;i<=length(a);i++)_ca[substr(a,i,1)]++;for(i=1;i<=length(b);i++)_cb[substr(b,i,1)]++;mtch=0;for(ch in _ca)if(ch in _cb)mtch+=(_ca[ch]<_cb[ch]?_ca[ch]:_cb[ch]);return mtch}
            {base=lower(basename($1));n=split(base,tokens,/[ .\-_]+/);best=0;for(t=1;t<=n;t++){tok=tokens[t];dist=levenshtein(ql,tok);maxl=(length(ql)>length(tok)?length(ql):length(tok));if(!maxl)continue;sim=1-dist/maxl;overlap=charoverlap(ql,tok)/length(ql);score=sim*0.6+overlap*0.4;if(score>best)best=score};if(best>=0.45){freq=$2*1000/(now-$3+1);printf "%06.4f|%015.4f|%s\n",best,freq,$1}}
        ' "$sdb" | sort -t'|' -k1,1rn -k2,2rn | cut -d'|' -f3-)
    fi
    printf '%s' "$result"
}

# check alias DB -- exact then fuzzy via same search passes on alias names
alias_hit=$(awk -F'|' -v a="$arg" '$1==a{print $2"|"$3; exit}' "$ALIASDB")
if [ -z "$alias_hit" ] && [ -s "$ALIASDB" ]; then
    now=$(date +%s)
    ql=$(echo "$arg" | tr '[:upper:]' '[:lower:]')
    # build temp DB with alias names as paths (score=1, epoch=now)
    alias_tmp=$(mktemp)
    awk -F'|' -v now="$now" '{printf "%s|1.0000|%d\n", $1, now}' "$ALIASDB" > "$alias_tmp"
    matched_alias=$(_search "$alias_tmp" "$ql" "$now" | head -1)
    rm -f "$alias_tmp"
    [ -n "$matched_alias" ] && alias_hit=$(awk -F'|' -v a="$matched_alias" '$1==a{print $2"|"$3; exit}' "$ALIASDB")
fi
if [ -n "$alias_hit" ]; then
    selected="${alias_hit%%|*}"
    alias_prog="${alias_hit##*|}"
    [ -n "$alias_prog" ] && [ ${#prog[@]} -eq 0 ] && prog=("$alias_prog")
    _bump "$selected"
elif [ -e "$arg" ]; then
    selected=$(realpath -- "$arg")
    _bump "$selected"
else
    now=$(date +%s)
    ql=$(echo "$arg" | tr '[:upper:]' '[:lower:]')

    result=$(_search "$DB" "$ql" "$now")

    [ -z "$result" ] && { echo "no match: $arg" >&2; exit 1; }

    if [ "$interactive" -eq 1 ]; then
        selected=$(printf '%s\n' "$result" | fzf --height=40% --reverse --exit-0)
    else
        selected=$(printf '%s\n' "$result" | head -1)
    fi

    [ -z "$selected" ] && exit 1
    _bump "$selected"
fi

if [ "$bg" -eq 1 ]; then mode=" -b"; elif [ "$DEFAULT_BG" -eq 1 ]; then mode=" -f"; else mode=""; fi
full_cmd="lup${mode}${prog:+ ${prog[*]}} $selected"

if [ ${#prog[@]} -eq 0 ] && [ -t 1 ]; then
    if [ "$portal" -eq 1 ]; then
        echo "$selected"
        exit 0
    elif [ -f "$selected" ]; then
        if ! command -v xdg-open &>/dev/null; then
            echo "error: opening a file needs xdg-open (xdg-utils), which isn't installed" >&2
            echo "  install it, then retry" >&2
            exit 1
        fi
        prog=("xdg-open")
    elif [ -d "$selected" ]; then
        for fm in thunar nautilus dolphin nemo pcmanfm; do
            if command -v "$fm" &>/dev/null; then prog=("$fm"); break; fi
        done
        [ ${#prog[@]} -eq 0 ] && { echo "$selected"; exit 0; }
    fi
fi

if [ ${#prog[@]} -gt 0 ]; then
    # for xdg-open, check if a handler exists first
    if [ "${prog[0]}" = "xdg-open" ]; then
        if ! command -v xdg-mime &>/dev/null; then
            echo "error: opening a file needs xdg-mime (xdg-utils), which isn't installed" >&2
            echo "  install it, then retry" >&2
            exit 1
        fi
        mime=$(xdg-mime query filetype "$selected" 2>/dev/null)
        handler=$(xdg-mime query default "$mime" 2>/dev/null)
        if [ -z "$handler" ]; then
            echo "error: no default app for '$mime'" >&2
            echo "  set one: xdg-mime default <app>.desktop $mime" >&2
            echo "  or run with: run <program> $(basename "$selected")" >&2
            exit 1
        fi
    fi
    if [ "$bg" -eq 1 ]; then
        nohup "${prog[@]}" "$selected" >/dev/null 2>&1 &
        pid=$!
        _log "$pid" "$full_cmd"
    else
        _log "exec" "$full_cmd"
        exec "${prog[@]}" "$selected"
    fi
else
    _log "-" "$full_cmd"
    echo "$selected"
fi

# -q: close the terminal window after launching
if [ "$quit_terminal" -eq 1 ]; then
    shell_pid=$(ps -o ppid= -p "$$" | tr -d ' ')
    terminal_pid=$(ps -o ppid= -p "$shell_pid" | tr -d ' ')
    { sleep 0.3; kill "$terminal_pid"; } &
fi
