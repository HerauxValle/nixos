#&help:"Deletes btrfs subvolume (WARNING: deletes all data!)"
function deletesubvol --description "Safely delete a btrfs subvolume with warnings"
    if test (count $argv) -ne 1
        echo "Usage: deletesubvol <path>"
        echo "Example: deletesubvol ~/.cache"
        return 1
    end

    set -l target_path (realpath $argv[1] 2>/dev/null; or echo $argv[1])

    # Check if path exists
    if not test -e "$target_path"
        echo "Error: Path '$target_path' does not exist"
        return 1
    end

    # Check if it's actually a subvolume
    if not sudo btrfs subvolume show "$target_path" &>/dev/null
        echo "Error: '$target_path' is not a btrfs subvolume"
        return 1
    end

    # Show warning
    set_color --bold red
    echo "⚠️  WARNING: THIS WILL PERMANENTLY DELETE ALL DATA IN THIS SUBVOLUME! ⚠️"
    set_color normal
    echo ""
    echo "Subvolume: $target_path"
    echo ""
    
    # Show contents preview
    echo "Contents preview:"
    ls -lh "$target_path" | head -10
    echo ""
    
    # Calculate size
    set -l size (du -sh "$target_path" 2>/dev/null | awk '{print $1}')
    echo "Approximate size: $size"
    echo ""
    
    set_color --bold yellow
    echo "Type 'DELETE' (all caps) to confirm deletion:"
    set_color normal
    read -P "> " confirm

    if test "$confirm" != "DELETE"
        echo "Aborted. Subvolume was NOT deleted."
        return 1
    end

    echo ""
    echo "Deleting subvolume..."
    sudo btrfs subvolume delete "$target_path"
    
    if test $status -eq 0
        set_color --bold green
        echo "✓ Subvolume deleted successfully"
        set_color normal
    else
        set_color --bold red
        echo "✗ Failed to delete subvolume"
        set_color normal
        return 1
    end
end