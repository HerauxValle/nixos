# &desc: "Fish shell command wrapper managing in-shell activation state transitions and path additions while passing through other requests."

# &desc: "Fish shell command wrapper managing in-shell activation state transitions and path additions while passing through other requests."

# Source this from config.fish (once). The real `venvctl` binary (from
# nix, on PATH) can only print VAR=value lines for activate/deactivate --
# a subprocess cannot mutate its parent shell's env. This function
# shadows that binary with a single fish function of the same name, so
# there's one command surface: `venvctl activate|deactivate` are handled
# right here (parsing the protocol and applying it to *this* shell);
# every other subcommand (list, update, help, anything added later) is
# passed straight through to the real binary via `command venvctl`. See
# docs/DECISIONS.md "Shim protocol" for why the split exists at all.

function venvctl --description 'Declarative venv control (activate/deactivate run in-shell, everything else passes through)'
    if test (count $argv) -lt 1
        command venvctl
        return $status
    end

    switch $argv[1]
        case activate
            if test (count $argv) -lt 2
                echo "usage: venvctl activate <name|path>" >&2
                return 1
            end

            set -l out (command venvctl activate $argv[2..-1])
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

        case deactivate
            command venvctl deactivate $VIRTUAL_ENV > /dev/null
            or return 1

            if set -q VENV_ACTIVE_BIN
                set -gx PATH (string match -v -- $VENV_ACTIVE_BIN $PATH)
                set -e VENV_ACTIVE_BIN
            end
            set -e VIRTUAL_ENV

        case '*'
            # list, update, help, -h/--help, unknown -- let the real
            # binary handle it (including its own error message/exit
            # code for genuinely unknown subcommands).
            command venvctl $argv
            return $status
    end
end
