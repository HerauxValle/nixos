#&help:"Queries files. Use "q help" for help."
function query --description "Ultimate Query: q name=test, ext=png/jpg, in=~/Docs, size>10mb, type=file"
    # Check for help
    if contains -- "help" $argv; or test -z "$argv"
        echo "Usage: q [options]"
        echo "Options (separate with commas, use / for OR):"
        echo "  name=   File name (regex)"
        echo "  ext=    Extension (e.g., png/jpg)"
        echo "  in=     Path to search (default: current)"
        echo "  size=   Size comparison (e.g., >1mb, <50kb)"
        echo "  type=   file or dir"
        return
    end

    set -l name (string match -r 'name=([^,]+)' "$argv" | line 2 | string replace -a '/' '|')
    set -l ext  (string match -r 'ext=([^,]+)'  "$argv" | line 2 | string replace -a '/' '|')
    set -l path (string match -r 'in=([^,]+)'   "$argv" | line 2; or echo ".")
    set -l size (string match -r 'size=([^,]+)' "$argv" | line 2)
    set -l type (string match -r 'type=([^,]+)' "$argv" | line 2)

    set -l nu_query "ls -f **/*"
    
    [ -n "$name" ]; and set nu_query "$nu_query | where name =~ '(?i)$name'"
    [ -n "$ext" ];  and set nu_query "$nu_query | where name =~ '(?i)\.($ext)\$'"
    [ -n "$size" ]; and set nu_query "$nu_query | where size $size"
    [ -n "$type" ]; and set nu_query "$nu_query | where type == '$type'"

    # 3. Execution
    builtin cd $path
    nu -c "$nu_query | sort-by modified -r"
    builtin cd - >/dev/null
end