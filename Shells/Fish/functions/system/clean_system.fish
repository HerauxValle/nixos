#&help:"Remove orphans, paccache, and pacman cache"
function clean-system
    set orphans (pacman -Qdtq)
    if test -n "$orphans"
        sudo pacman -Rns $orphans
    end
    sudo paccache -r
    sudo pacman -Sc
end
