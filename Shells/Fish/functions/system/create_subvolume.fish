#&help:"Creates btrfs subvolume from existing dir"
function createsubvol --description "Creates a btrfs subvolume from existing directory"
    if test (count $argv) -ne 1
        echo "Usage: createsubvol <path>"
        echo "Example: createsubvol ~/.local/share/Steam"
        return 1
    end

    set -l target_path (realpath $argv[1] 2>/dev/null; or echo $argv[1])
    set -l backup_path "$target_path-backup"

    # Check if path exists
    if not test -e "$target_path"
        echo "Error: Path '$target_path' does not exist"
        return 1
    end

    # Confirm with user
    echo "This will convert '$target_path' to a btrfs subvolume."
    echo "Data will be temporarily moved to '$backup_path'"
    read -P "Continue? [y/N] " -n 1 confirm
    echo

    if test "$confirm" != "y" -a "$confirm" != "Y"
        echo "Aborted."
        return 1
    end

    # Backup
    echo "Moving data to backup..."
    mv "$target_path" "$backup_path"
    or begin
        echo "Error: Failed to move directory"
        return 1
    end

    # Create subvolume
    echo "Creating subvolume..."
    sudo btrfs subvolume create "$target_path"
    or begin
        echo "Error: Failed to create subvolume, restoring backup..."
        mv "$backup_path" "$target_path"
        return 1
    end

    # Move data back
    echo "Restoring data..."
    mv "$backup_path"/* "$target_path/" 2>/dev/null
    cp -a "$backup_path"/. "$target_path/" 2>/dev/null  # Copy everything including hidden
    rm -rf "$backup_path"  # Then remove backup
    rmdir "$backup_path"

    # Fix permissions
    echo "Fixing permissions..."
    sudo chown -R $USER:$USER "$target_path"

    echo "✓ Subvolume created successfully at '$target_path'"
    echo "Verify with: sudo btrfs subvolume list /"
end