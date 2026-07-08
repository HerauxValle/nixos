#&help:"Counts tokens chars and lines of files and folders"
function countlines
    set calc_tokens 0
    set TARGET ""
    set has_tiktoken 1  # default: not available

    # parse args
    for arg in $argv
        if test "$arg" = "-t"
            set calc_tokens 1
        else
            set TARGET $arg
        end
    end

    # prompt if no path given
    if test -z "$TARGET"
        read -P "Enter file or directory: " TARGET
    end

    if not test -e "$TARGET"
        echo "Invalid path"
        return 1
    end

    set total_lines 0
    set total_chars 0
    set total_tokens 0

    if test -f "$TARGET"
        set files $TARGET
    else
        set files (find "$TARGET" -type f)
    end

    # only check tiktoken if needed
    if test $calc_tokens -eq 1
        python -c "import tiktoken" >/dev/null 2>&1
        set has_tiktoken $status
    end

    for f in $files
        set lines (wc -l < "$f")
        set chars (wc -m < "$f")

        set total_lines (math $total_lines + $lines)
        set total_chars (math $total_chars + $chars)

        if test $calc_tokens -eq 1; and test $has_tiktoken -eq 0
            set tokens (python -c "
import tiktoken
with open('$f','r',encoding='utf-8',errors='ignore') as file:
    print(len(tiktoken.get_encoding('cl100k_base').encode(file.read())))
")
            set total_tokens (math $total_tokens + $tokens)
        end
    end

    echo "TOTAL:"
    echo "  lines: $total_lines"
    echo "  chars: $total_chars"

    if test $calc_tokens -eq 1
        if test $has_tiktoken -eq 0
            echo "  tokens: $total_tokens"
        else
            echo "  tokens: (install with: pip install tiktoken)"
        end
    end
end

#&help:"Calculates the tokens of a file"
function tokens
    read -P "File path: " f
    python -c "import tiktoken;print(len(tiktoken.get_encoding('cl100k_base').encode(open('$f').read())))"
end