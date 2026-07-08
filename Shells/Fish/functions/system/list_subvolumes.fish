#&help:"Lists user btrfs subvolumes"
function listsubvol --description "Lists user btrfs subvolumes"
    sudo btrfs subvolume list / | grep -E 'herauxvalle|@home|@log|@pkg'
end