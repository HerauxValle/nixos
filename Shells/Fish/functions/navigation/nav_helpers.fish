#&help:"Lists child directories"
#&help:"fzf child dir/file picker with open actions"
function into
    # Get all items (visible and hidden) using fish glob
    # The trick: use a for loop which handles empty globs gracefully
    set -l items
    
    # Get visible items
    for item in *
        if test -e $item
            set -a items $item
        end
    end
    
    # Get hidden items (excluding . and ..)
    for item in .*
        if test -e $item; and test $item != "."; and test $item != ".."
            set -a items $item
        end
    end
    
    # Check if there are any items
    if test (count $items) -eq 0
        echo "Directory is empty"
        return 1
    end
    
    # Add icons and indicators
    set -l display_items
    for item in $items
        if test -d $item
            set -a display_items "📁 $item"
        else
            # Get file icon based on extension
            set -l icon "📄"
            switch (string lower (path extension $item))
                case .pdf
                    set icon "📕"
                case .txt .md .doc .docx
                    set icon "📝"
                case .jpg .jpeg .png .gif .webp .svg
                    set icon "🖼️"
                case .mp3 .wav .flac .ogg
                    set icon "🎵"
                case .mp4 .mkv .avi .mov
                    set icon "🎬"
                case .zip .tar .gz .7z .rar
                    set icon "📦"
                case .sh .bash .fish
                    set icon "🐚"
                case .py
                    set icon "🐍"
                case .js .ts .jsx .tsx
                    set icon "📜"
                case .html .css
                    set icon "🌐"
                case .json .xml .yaml .yml .toml
                    set icon "⚙️"
                case .conf .config .ini
                    set icon "🔧"
            end
            set -a display_items "$icon $item"
        end
    end
    
    # Use fzf to select an item
    set -l selected (printf '%s\n' $display_items | fzf --height=40% --reverse --prompt="Select: ")
    
    if test -z "$selected"
        return 0
    end
    
    # Remove icon and spaces from selection
    set selected (string replace -r '^[^ ]+ ' '' $selected)
    
    # Check if it's a directory or file
    if test -d $selected
        cd $selected
    else if test -f $selected
        # Ask how to open the file
        set -l action (printf "Default app\nOpen with...\nEdit in terminal" | fzf --height=40% --reverse --prompt="How to open '$selected'? ")
        
        switch $action
            case "Default app"
                xdg-open $selected
            case "Open with..."
                # Get list of common applications
                set -l apps "firefox" "chromium" "kate" "vim" "nvim" "code" "dolphin" "vlc" "mpv" "gimp" "inkscape"
                set -l chosen_app (printf '%s\n' $apps | fzf --height=40% --reverse --prompt="Select app: ")
                if test -n "$chosen_app"
                    $chosen_app $selected &
                end
            case "Edit in terminal"
                $EDITOR $selected
        end
    end
end