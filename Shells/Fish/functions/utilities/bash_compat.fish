# --- BASHRC ALIAS & FUNCTION CHECKER ---
#&help:"Run bash aliases/functions from bashrc"
function :: --description "Run bash aliases/functions from bashrc"
    if test (count $argv) -eq 0
        echo "Usage: :: <bash_alias_or_function> [args...]" >&2
        return 1
    end

    set -l command_name $argv[1]

    if bash -i -c "type -t '$command_name'" 2>/dev/null | grep -qE '^(alias|function)$'
        
        # Execute the alias/function
        bash -i -c "shopt -s expand_aliases; $argv"
        return $status
    end

    echo "fish: '::' is restricted to bash aliases/functions." >&2
    echo "      '$command_name' was not found or is a standard executable/builtin." >&2
    return 127
end