#&help:"Used for services.py/sh"
function rsdclear
    set loops (losetup -a | cut -d: -f1)
    set sessions (tmux list-sessions -F '#S' 2>/dev/null)

    if test (count $loops) -eq 0
        echo "No loop devices found"
    else
        echo "Loop devices found:"
        printf "%s\n" $loops

        for l in $loops
            set mnts (mount | grep $l | awk '{print $3}')
            for m in $mnts
                echo "Unmounting $m"
                sudo umount -lf $m
            end
        end

        for m in (ls /dev/mapper 2>/dev/null)
            if sudo cryptsetup status $m 2>/dev/null | grep -q loop
                echo "Closing LUKS mapper $m"
                sudo cryptsetup close $m
            end
        end

        echo "Detaching loop devices"
        sudo losetup -D
    end

    if test (count $sessions) -eq 0
        echo "No tmux sessions found"
    else
        echo "Tmux sessions found:"
        printf "%s\n" $sessions
        for s in $sessions
            echo "Killing tmux session $s"
            tmux kill-session -t $s
        end
    end
end

#&help:"Run services.py and log everything"
function rsdlog
    set script /home/herauxvalle/Projects/SimpleDocker/Services/services.py
    set log (dirname $script)/services.log

    : > $log
    echo "Logging to $log"

    script -q -c "python $script" $log
end

#&help:"Consecutive execution"
function rsd
    rsdclear
    rsdlog
end