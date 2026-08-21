#&help:"Shuffle and cycle through images in a folder via Gwenview"
function shuffle_images
    argparse 'p/path=' 'c/cycle=' -- $argv
    or return 1

    set -l target_dir $_flag_path
    set -l cycle_time $_flag_cycle

    # Defaults
    test -z "$target_dir"; and set target_dir .
    test -z "$cycle_time"; and set cycle_time 5

    # Check dependencies
    if not command -q gwenview
        echo "Error: gwenview is not installed."
        return 1
    end

    echo "Shuffling images from $target_dir every $cycle_time seconds... (Press Ctrl+C to stop)"

    while true
        # Collect all image files recursively, shuffle them, and filter out empty lines
        set -l images (find -L "$target_dir" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.bmp" \) | shuf)

        if test (count $images) -eq 0
            echo "No image files found in $target_dir"
            return 1
        end

        for img in $images
            # Open image in Gwenview in the background
            gwenview "$img" &>/dev/null &
            set -l gwen_pid (jobs -p | tail -n 1)

            sleep $cycle_time

            # Close previous Gwenview instance before opening the next
            if test -n "$gwen_pid"
                kill $gwen_pid &>/dev/null
            end
        end
    end
end

# Alias shortcut
alias gshuffle=shuffle_images
