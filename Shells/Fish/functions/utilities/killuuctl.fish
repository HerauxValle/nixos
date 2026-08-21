#&help:"Kill uuctl and whatever menu picker (dmenu/rofi/wofi/etc.) it spawned"
function killuuctl
    set pids (pgrep -f uuctl)

    if test (count $pids) -eq 0
        echo "uuctl not running"
        return
    end

    for pid in $pids
        # kill uuctl's child (the actual menu picker window -- backend varies,
        # so this is found by process tree, not by hardcoding dmenu/rofi/etc.)
        pkill -9 -P $pid 2>/dev/null
        kill -9 $pid 2>/dev/null
    end
    echo "Killed uuctl and its menu picker"
end
