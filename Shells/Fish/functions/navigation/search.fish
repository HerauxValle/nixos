#&help:"JQ wrapper for "find"""
#&help:"Interactive file/content search with fzf"
function search --description "Interactive file/content search with live fzf"
    # First, ask what type of search
    set -l search_type (printf "Filename\nFile content\nExtension\nFile type\nSize\nDate modified" | fzf --height=40% --reverse --prompt="What to search for? ")
    
    if test -z "$search_type"
        return 0
    end
    
    # Ask where to search
    set -l search_location (printf "Home directory\nSpecific directory\nEverywhere" | fzf --height=40% --reverse --prompt="Where to search? ")
    
    if test -z "$search_location"
        return 0
    end
    
    switch $search_location
        case "Home directory"
            set search_path ~
        case "Specific directory"
            set -l temp_file (mktemp)
            yazi --chooser-file=$temp_file
            if test -s $temp_file
                set search_path (cat $temp_file)
                rm $temp_file
            else
                rm $temp_file
                echo "No directory selected"
                return 0
            end
        case "Everywhere"
            set search_path /
        case '*'
            return 0
    end
    
    # Live search with fzf based on type
    switch $search_type
        case "Filename"
            set -l selected (find $search_path -type f -o -type d 2>/dev/null | fzf \
                --height=80% \
                --reverse \
                --prompt="Search filename: " \
                --preview 'if test -d {}; echo "📁 Directory"; ls -lah {}; else echo "📄 File"; head -n 50 {}; end' \
                --preview-window=right:50%)
            
        case "File content"
            echo "Indexing files for content search..."
            set -l all_files (find $search_path -type f 2>/dev/null)
            set -l selected (printf '%s\n' $all_files | fzf \
                --height=80% \
                --reverse \
                --prompt="Search content: " \
                --preview 'grep --color=always -i {q} {} 2>/dev/null || cat {}' \
                --preview-window=right:50% \
                --bind 'change:reload:grep -l {q} '$search_path' -r 2>/dev/null || true')
            
        case "Extension"
            set -l selected (find $search_path -type f 2>/dev/null | fzf \
                --height=80% \
                --reverse \
                --prompt="Search extension: " \
                --preview 'echo "📄 {}"; head -n 50 {}' \
                --preview-window=right:50% \
                --query=".")
            
        case "File type"
            set -l ftype (printf "Directory\nRegular file\nSymbolic link" | fzf --height=40% --reverse --prompt="File type: ")
            switch $ftype
                case "Directory"
                    set -l selected (find $search_path -type d 2>/dev/null | fzf --height=80% --reverse --prompt="Select directory: " --preview 'ls -lah {}')
                case "Regular file"
                    set -l selected (find $search_path -type f 2>/dev/null | fzf --height=80% --reverse --prompt="Select file: " --preview 'head -n 50 {}')
                case "Symbolic link"
                    set -l selected (find $search_path -type l 2>/dev/null | fzf --height=80% --reverse --prompt="Select symlink: ")
                case '*'
                    return 0
            end
            
        case "Size"
            set -l size_filter (printf "+100M (larger than 100MB)\n-1M (smaller than 1MB)\n+1G (larger than 1GB)\n-100k (smaller than 100KB)" | fzf --height=40% --reverse --prompt="Size filter: ")
            set -l size_val (echo $size_filter | awk '{print $1}')
            if test -n "$size_val"
                set -l selected (find $search_path -type f -size $size_val 2>/dev/null | fzf --height=80% --reverse --prompt="Select file: " --preview 'ls -lh {}; echo "---"; head -n 30 {}')
            else
                return 0
            end
            
        case "Date modified"
            set -l date_filter (printf "-1 (last 24 hours)\n-7 (last week)\n-30 (last month)\n+30 (older than 30 days)\n+365 (older than 1 year)" | fzf --height=40% --reverse --prompt="Date filter: ")
            set -l days (echo $date_filter | awk '{print $1}')
            if test -n "$days"
                set -l selected (find $search_path -type f -mtime $days 2>/dev/null | fzf --height=80% --reverse --prompt="Select file: " --preview 'ls -lh {}; echo "---"; head -n 30 {}')
            else
                return 0
            end
    end
    
    if test -z "$selected"
        return 0
    end
    
    # Handle selection
    if test -d $selected
        cd $selected
        echo "Changed to: $selected"
    else if test -f $selected
        set -l action (printf "Default app\nOpen with...\nEdit in terminal\nShow in file manager\nCopy path" | fzf --height=40% --reverse --prompt="Open: ")
        
        switch $action
            case "Default app"
                xdg-open $selected &
            case "Open with..."
                set -l apps "firefox" "chromium" "kate" "vim" "nvim" "code" "dolphin" "vlc" "mpv" "gimp" "inkscape"
                set -l chosen_app (printf '%s\n' $apps | fzf --height=40% --reverse --prompt="App: ")
                if test -n "$chosen_app"
                    $chosen_app $selected &
                end
            case "Edit in terminal"
                $EDITOR $selected
            case "Show in file manager"
                dolphin (dirname $selected) &
            case "Copy path"
                echo -n $selected | wl-copy
                echo "Copied: $selected"
        end
    end
end