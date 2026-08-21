#&help:"Schedule shutdown: sleep_at 11pm / 30m / cancel"
function sleep_at --description "Schedule system shutdown"
    if test (count $argv) -eq 0
        echo "Usage: sleep_at <time|duration|cancel>"
        return
    end

    # join all args → supports "11:30 pm"
    set arg (string lower (string join " " $argv))

    if test "$arg" = "cancel"
        sudo shutdown -c
        return
    end

    if test "$arg" = "0"
        sudo shutdown now
        return
    end

    # --- TIME FORMAT (flexible parsing) ---
    if string match -rq '^[0-9]{1,2}(:[0-9]{2})?\s*([ap]m)?$' -- $arg
        set now (date +%s)

        # try today first
        set target (date -d "today $arg" +%s 2>/dev/null)

        # fallback (for weird formats like "10pm")
        if test -z "$target"
            set target (date -d "$arg" +%s 2>/dev/null)
        end

        # if still invalid → abort
        if test -z "$target"
            echo "Invalid time format"
            return
        end

        # if in past → tomorrow
        if test $target -le $now
            set target (date -d "tomorrow $arg" +%s)
        end

        set diff (math "$target - $now")
        set minutes (math "ceil($diff / 60)")

        echo "Shutdown scheduled in $minutes minute(s)"
        sudo shutdown +$minutes
        return
    end

    # --- DURATION FORMAT ---
    if string match -rq '^[0-9]+[smhd]$' -- $arg
        set num (string sub -s 1 -l (math (string length $arg) - 1) $arg)
        set unit (string sub -s (string length $arg) $arg)

        switch $unit
            case s
                set seconds $num
            case m
                set seconds (math "$num * 60")
            case h
                set seconds (math "$num * 3600")
            case d
                set seconds (math "$num * 86400")
        end

        set minutes (math "ceil($seconds / 60)")

        if test $minutes -le 0
            sudo shutdown now
        else
            echo "Shutdown scheduled in $minutes minute(s)"
            sudo shutdown +$minutes
        end
        return
    end

    echo "Usage:"
    echo "  sleep <time>[s|m|h|d]"
    echo "  sleep HH:MM"
    echo "  sleep HH:MM am/pm"
    echo "  sleep cancel"
end