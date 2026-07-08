#&help:"Modular system updater (--yay/--pac/--all, combinable)"
function update --description "Run one or more update modules; defaults to all if none given"
    # --- module registry ---------------------------------------------------
    # name -> binary -> command to run
    set -l module_names yay pac
    set -l module_bins   yay pacman
    set -l module_cmds \
        "yay -Syu --noconfirm --removemake --cleanafter" \
        "sudo pacman -Syu --noconfirm"

    # --- arg parsing ---------------------------------------------------
    set -l requested
    set -l show_help false

    for arg in $argv
        switch $arg
            case --all
                set requested $module_names
            case -h --help
                set show_help true
            case '--*'
                set -l name (string sub -s 3 -- $arg)
                if contains -- $name $module_names
                    set -a requested $name
                else
                    set_color red; echo "update: unknown module '$name'"; set_color normal
                    echo "Available modules:" (string join ', ' $module_names)
                    return 1
                end
            case '*'
                set_color red; echo "update: unrecognized argument '$arg'"; set_color normal
                return 1
        end
    end

    if test "$show_help" = true
        echo "Usage: update [--module ...] [--all]"
        echo "Modules:" (string join ', ' $module_names)
        echo "No args runs all modules."
        return 0
    end

    if test (count $requested) -eq 0
        set requested $module_names
    end

    # dedupe while preserving order
    set -l seen
    set -l ordered
    for m in $requested
        if not contains -- $m $seen
            set -a seen $m
            set -a ordered $m
        end
    end
    set requested $ordered

    # --- run ---------------------------------------------------
    # prime sudo once up front so nothing prompts again mid-run
    sudo -v; or return 1

    # keep the sudo timestamp alive for the duration of the run
    fish -c 'while true; sudo -nv 2>/dev/null; sleep 60; end' &
    set -l keepalive_pid $last_pid
    function _update_stop_keepalive --on-process-exit %self
        kill $keepalive_pid 2>/dev/null
    end

    for mod in $requested
        set -l idx (contains -i -- $mod $module_names)
        set -l bin $module_bins[$idx]
        set -l cmd $module_cmds[$idx]

        if not command -q $bin
            set_color yellow; echo "⚠ Skipping '$mod': '$bin' not found"; set_color normal
            continue
        end

        set_color cyan; echo "==> Running $mod ($cmd)"; set_color normal
        eval $cmd
        if test $status -ne 0
            set_color red; echo "✗ $mod failed (exit $status)"; set_color normal
        end
    end
end
