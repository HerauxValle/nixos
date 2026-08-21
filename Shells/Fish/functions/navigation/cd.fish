#&help:"Advanced CD with run + zoxide"
function cd
    function _add
        run $argv > /dev/null
        zoxide add $argv
    end

    if test (count $argv) -eq 0
        builtin cd
        _add (pwd)
        return 0
    end

    if test "$argv[1]" = "!"
        builtin cd /
        _add /
        return 0
    end

    if builtin cd $argv 2>/dev/null
        _add (pwd)
        return 0
    end

    set -l target (run -f $argv 2>/dev/null)
    if test -n "$target"; and builtin cd $target 2>/dev/null
        _add (pwd)
        return 0
    end

    set -l target (zoxide query -- $argv 2>/dev/null)
    if test -n "$target"; and builtin cd $target 2>/dev/null
        _add (pwd)
        return 0
    end

    echo "cd: no such directory: $argv" >&2
    set -l suggestions (zoxide query -l -- $argv 2>/dev/null | head -n 5)
    if test -n "$suggestions"
        echo "Did you mean one of these?" >&2
        printf '  %s\n' $suggestions >&2
    end
    return 1
end
