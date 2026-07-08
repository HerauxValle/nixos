# --- SYNTAX CHECKER (fish command_not_found) ---
function fish_command_not_found --on-event fish_command_not_found
    set -l cmd $argv[1]
    set -l found_in
    
    # Check each shell
    if bash -i -c "command -v $cmd" 2>/dev/null | grep -q "."
        set found_in bash
    else if nu -c "which $cmd | length" 2>/dev/null | string match -q -r '[1-9]'
        set found_in nu
    else if pwsh -NoProfile -Command "Get-Command '$cmd' -ErrorAction SilentlyContinue" >/dev/null 2>&1
        set found_in pwsh
    end
    
    if test -n "$found_in"
        echo "fish: Unknown command '$cmd', but found in $found_in shell. Use :b, :n, or :p to run." >&2
        return 127
    else
        echo "fish: Unknown command '$cmd'. Not found in any shell (fish, bash, nu, pwsh)." >&2
        echo "      Type \"help\" for a list of Aliases, Functions, Abbreviations and Flags." 
        return 127
    end
end