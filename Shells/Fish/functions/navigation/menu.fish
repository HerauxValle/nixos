#&help:"fzf-based app launcher with custom entries"
function launcher --description "fzf-based application launcher (rofi replacement)"
    set -l cache_file ~/.cache/launcher_apps
    set -l custom_file ~/.cache/launcher_custom
    
    # Ensure files exist
    if not test -f $custom_file
        touch $custom_file
    end
    
    # Check if cache exists
    if test -f $cache_file
        set apps (cat $cache_file)
        
        # Update cache in background continuously
        fish -c "
            while true
                sleep 1
                set -l desktop_files (find -L /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | head -500)
                
                set -l new_apps
                for file in \$desktop_files
                    set -l name (grep '^Name=' \$file | head -n1 | cut -d= -f2)
                    set -l exec (grep '^Exec=' \$file | head -n1 | cut -d= -f2 | sed 's/%[uUfF]//' | sed 's/  */ /g')
                    
                    if test -n \"\$name\" -a -n \"\$exec\"
                        set -a new_apps \"\$name|\$exec\"
                    end
                end
                
                printf '%s\n' \$new_apps | sort -u > $cache_file
            end
        " &
        set -l bg_pid (jobs -lp | tail -1)
    else
        set apps
        mkdir -p ~/.cache

        # Build cache in background, show empty menu immediately
        fish -c "
            set -l desktop_files (timeout 5 find -L /usr/share/applications ~/.local/share/applications -name '*.desktop' 2>/dev/null | head -500)

            set -l new_apps
            for file in \$desktop_files
                set -l name (grep '^Name=' \$file | head -n1 | cut -d= -f2)
                set -l exec (grep '^Exec=' \$file | head -n1 | cut -d= -f2 | sed 's/%[uUfF]//' | sed 's/  */ /g')

                if test -n \"\$name\" -a -n \"\$exec\"
                    set -a new_apps \"\$name|\$exec\"
                end
            end

            printf '%s\n' \$new_apps | sort -u > $cache_file
        " >/dev/null 2>&1 &
    end
    
    # Add custom entries
    if test -s $custom_file
        set -l custom_apps (cat $custom_file)
        set apps (printf '%s\n' $apps $custom_apps | sort -u)
    end
    
    # Build sectioned display
    set -l custom_names (cat $custom_file 2>/dev/null | sed 's/|.*//')
    set -l app_names (cat $cache_file 2>/dev/null | sed 's/|.*//' | sort -u)

    set -l selected (printf '%s\n' "Menu Settings" "---" $custom_names "---" $app_names | fzf \
        --height=100% \
        --reverse \
        --prompt='Launch: ' \
        --no-preview \
        --bind 'result:reload-sync(echo "Menu Settings"; echo "---"; cat '$custom_file' 2>/dev/null | sed "s/|.*//" ; echo "---"; cat '$cache_file' 2>/dev/null | sed "s/|.*//" | sort -u)')
    
    # Kill background updater
    if set -q bg_pid
        kill $bg_pid 2>/dev/null
    end
    
    if test -z "$selected"
        return 0
    end

    if test "$selected" = "---"
        launcher
        return 0
    end

    # Handle settings
    if test "$selected" = "Menu Settings"
        set -l action (printf "+ Add\n- Remove\n~ Modify" | fzf --height=40% --reverse --prompt="Settings: ")
        
        switch $action
            case "+ Add"
                set -l temp_file (mktemp)
                $EDITOR $temp_file
                set -l exec_path (string trim (cat $temp_file))
                rm $temp_file

                if test -n "$exec_path"
                    set -l default_name (basename (string split ' ' -- $exec_path)[1] | sed 's/\.[^.]*$//')

                    set -l custom_name (echo $default_name | fzf \
                        --height=40% \
                        --reverse \
                        --prompt="Enter name: " \
                        --print-query \
                        --bind 'enter:print-query' | tail -n1)

                    if test -z "$custom_name"
                        set custom_name $default_name
                    end

                    echo "$custom_name|$exec_path" >> $custom_file
                else
                    launcher
                    return 0
                end
                
            case "- Remove"
                if not test -s $custom_file
                    launcher
                    return 0
                end
                
                set -l custom_entries (cat $custom_file)
                set -l to_remove (printf '%s\n' $custom_entries | sed 's/|.*//' | fzf --height=40% --reverse --prompt="Remove: ")
                
                if test -n "$to_remove"
                    set -l confirm (printf "Yes, delete '$to_remove'\nNo, cancel" | fzf --height=40% --reverse --prompt="Confirm: ")
                    
                    if test "$confirm" = "Yes, delete '$to_remove'"
                        set -l temp (mktemp)
                        grep -v "^$to_remove|" $custom_file > $temp
                        mv $temp $custom_file
                    end
                end
                
            case "~ Modify"
                if not test -s $custom_file
                    launcher
                    return 0
                end
                
                set -l custom_entries (cat $custom_file)
                set -l to_modify (printf '%s\n' $custom_entries | sed 's/|.*//' | fzf --height=40% --reverse --prompt="Modify: ")
                
                if test -z "$to_modify"
                    launcher
                    return 0
                end
                
                set -l modify_what (printf "Name\nCommand" | fzf --height=40% --reverse --prompt="Modify what? ")
                
                switch $modify_what
                    case "Name"
                        set -l new_name (echo $to_modify | fzf \
                            --height=40% \
                            --reverse \
                            --prompt="New name: " \
                            --print-query \
                            --bind 'enter:print-query' | tail -n1)
                        
                        if test -n "$new_name"
                            set -l old_exec (grep "^$to_modify|" $custom_file | cut -d'|' -f2)
                            set -l temp (mktemp)
                            grep -v "^$to_modify|" $custom_file > $temp
                            echo "$new_name|$old_exec" >> $temp
                            mv $temp $custom_file
                        end
                        
                    case "Command"
                        set -l old_exec (grep "^$to_modify|" $custom_file | cut -d'|' -f2)
                        set -l temp_file (mktemp)
                        echo $old_exec > $temp_file
                        $EDITOR $temp_file
                        set -l new_path (string trim (cat $temp_file))
                        rm $temp_file

                        if test -n "$new_path"
                            set -l temp (mktemp)
                            grep -v "^$to_modify|" $custom_file > $temp
                            echo "$to_modify|$new_path" >> $temp
                            mv $temp $custom_file
                        end
                end
                
            case '*'
                launcher
                return 0
        end
        
        launcher
        return 0
    end
    
    set -l exec_cmd (printf '%s\n' $apps (cat $custom_file 2>/dev/null) | grep "^$selected|" | head -n1 | cut -d'|' -f2)
    if test -n "$exec_cmd"
        hyprctl dispatch exec "$exec_cmd"
    end
end