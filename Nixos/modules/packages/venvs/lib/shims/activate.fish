# Source this from config.fish (once). venvctl itself never touches your
# shell's env directly -- it only prints VAR=value lines, since a
# subprocess cannot mutate its parent shell. These two functions are the
# only shell-specific code in the whole system; venvctl and everything
# under lib/ stays fish/bash-agnostic. See docs/DECISIONS.md "Shim
# protocol" for the full reasoning.

function venv-activate --description 'Activate a declared nix venv by name or path'
    if test (count $argv) -lt 1
        echo "usage: venv-activate <name|path>" >&2
        return 1
    end

    set -l out (venvctl activate $argv[1])
    or return 1

    for line in $out
        set -l key (string split -m1 = $line)[1]
        set -l val (string split -m1 = $line)[2]

        switch $key
            case VIRTUAL_ENV
                set -gx VIRTUAL_ENV $val
            case PATH_PREPEND
                set -gx VENV_ACTIVE_BIN $val
                fish_add_path -g $val
        end
    end
end

function venv-deactivate --description 'Deactivate the currently active nix venv'
    if set -q VENV_ACTIVE_BIN
        set -gx PATH (string match -v -- $VENV_ACTIVE_BIN $PATH)
        set -e VENV_ACTIVE_BIN
    end
    set -e VIRTUAL_ENV
end
