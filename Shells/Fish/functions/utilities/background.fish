# --- BACKGROUND RUNNER ---
#&help:"Run a command in the background via nohup, suppressing all output"
function background --description "Run a command in the background via nohup, suppressing all output"
    if test (count $argv) -eq 0
        echo "Usage: background <command> [args...]" >&2
        return 1
    end
    nohup $argv > /dev/null 2>&1 &
end
