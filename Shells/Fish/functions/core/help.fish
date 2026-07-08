function help --description "List tagged aliases, functions, abbreviations, and flags"
    # 1. Path Setup
    set -l current_dir (dirname (realpath (status filename)))
    while test "$current_dir" != "/" -a ! -d "$current_dir/Shells"
        set current_dir (dirname $current_dir)
    end
    set -l shells_root "$current_dir/Shells"

    set -l c_header (set_color --bold white)
    set -l c_border (set_color black)
    set -l c_name   (set_color green)
    set -l c_desc   (set_color yellow)
    set -l c_reset  (set_color normal)

    set -l tmp_list (mktemp)

    # 2. Advanced Parser
    find "$shells_root" -path "*/Backup" -prune -o -path "*/.git" -prune -o -type f -print0 2>/dev/null | xargs -0 awk -v root="$shells_root" '
        BEGIN { map["Bash"] = "B"; map["Fish"] = "F"; map["Nu"] = "N"; map["Pwsh"] = "P"; }
        
        FNR == 1 {
            rel_path = FILENAME; sub(root "/", "", rel_path);
            split(rel_path, p, "/"); s_char = (map[p[1]] ? map[p[1]] : "?");
        }

        {
            if ($0 ~ /#&help:/) {
                match($0, /#&help:"(.+)"/, arr);
                desc = arr[1];
                
                line = $0;
                sub(/#&help:?"[^"]+"/, "", line);
                
                name = find_name(line);
                if (name == "") {
                    getline next_line;
                    name = find_name(next_line);
                }

                if (name != "" && name != "help") {
                    print type "|" s_char "|" name "|" desc;
                }
                desc = ""; name = ""; type = "";
            }
        }

        function find_name(str) {
            # 1. Alias
            if (str ~ /[[:space:]]*alias[[:space:]]+[^[:space:]=]+/) {
                type = "ALIAS"; match(str, /alias[[:space:]]+([^[:space:]=]+)/, n); return n[1];
            }
            # 2. Function
            if (str ~ /[[:space:]]*function[[:space:]]+[^[:space:]\(]+/) {
                type = "FUNC"; match(str, /function[[:space:]]+([^[:space:]\(]+)/, n); return n[1];
            }
            # 3. Abbreviation (Fish style)
            if (str ~ /[[:space:]]*abbr[[:space:]]+/) {
                type = "ABBR";
                # Extract the first word that doesnt start with - (the name)
                split(str, parts, " ");
                for (i in parts) {
                    if (parts[i] ~ /abbr/) continue;
                    if (parts[i] ~ /^-/) continue;
                    return parts[i];
                }
            }
            # 4. Flags / Set Variables
            if (str ~ /[[:space:]]*set[[:space:]]+/) {
                type = "FLAG";
                split(str, parts, " ");
                for (i in parts) {
                    if (parts[i] ~ /set/) continue;
                    if (parts[i] ~ /^-/) continue;
                    return parts[i];
                }
            }
            # 5. Bash/Shell name()
            if (str ~ /^[[:space:]]*[^[:space:]\(]+\(\)/) {
                type = "FUNC"; match(str, /([^[:space:]\(]+)\(\)/, n); return n[1];
            }
            return "";
        }
    ' | sort -t '|' -k 3 | uniq > "$tmp_list"

    # 3. Table Rendering (with ... truncation)
    set -l w_type 8
    set -l w_src 5
    set -l w_name 22
    set -l w_desc (math "$COLUMNS - $w_type - $w_src - $w_name - 5")
    test "$w_desc" -lt 15; and set w_desc 15

    function truncate_cell
        set -l text $argv[1]; set -l max_w $argv[2]
        if test (string length "$text") -gt "$max_w"
            echo (string sub -l (math "$max_w - 1") "$text")"…"
        else; echo "$text"; end
    end

    echo -e "$c_border┌"(string repeat -n $w_type "─")"┬"(string repeat -n $w_src "─")"┬"(string repeat -n $w_name "─")"┬"(string repeat -n $w_desc "─")"┐$c_reset"
    echo -e "$c_border│$c_header"(string pad -r -w $w_type " TYPE")"$c_border│$c_header"(string pad -r -w $w_src " SRC")"$c_border│$c_header"(string pad -r -w $w_name " NAME")"$c_border│$c_header"(string pad -r -w $w_desc " DESCRIPTION")"$c_border│$c_reset"
    echo -e "$c_border├"(string repeat -n $w_type "─")"┼"(string repeat -n $w_src "─")"┼"(string repeat -n $w_name "─")"┼"(string repeat -n $w_desc "─")"┤$c_reset"

    while read -l line
        set -l p (string split "|" "$line")
        set -l t (truncate_cell "$p[1]" $w_type)
        set -l s (truncate_cell "  $p[2]" $w_src)
        set -l n (truncate_cell " $p[3]" $w_name)
        set -l d (truncate_cell " $p[4]" $w_desc)

        # Color Logic
        set -l t_col $c_reset
        switch $p[1]
            case FUNC; set t_col (set_color --bold magenta)
            case ALIAS; set t_col (set_color --bold cyan)
            case ABBR; set t_col (set_color --bold yellow)
            case FLAG; set t_col (set_color --bold green)
        end
        
        set -l s_col $c_reset; test "$p[2]" = "F"; and set s_col (set_color --bold blue); test "$p[2]" = "B"; and set s_col (set_color --bold red)

        echo -e "$c_border│$t_col"(string pad -r -w $w_type "$t")"$c_border│$s_col"(string pad -r -w $w_src "$s")"$c_border│$c_name"(string pad -r -w $w_name "$n")"$c_border│$c_desc"(string pad -r -w $w_desc "$d")"$c_border│$c_reset"
    end < "$tmp_list"

    echo -e "$c_border└"(string repeat -n $w_type "─")"┴"(string repeat -n $w_src "─")"┴"(string repeat -n $w_name "─")"┴"(string repeat -n $w_desc "─")"┘$c_reset"
    rm "$tmp_list"
end