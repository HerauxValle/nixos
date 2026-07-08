#&help:"Update pacman + ignored pkgs"
function pacman
    sudo /usr/bin/pacman $argv

    # check if this is an install/upgrade command
    if contains -q "-S" $argv
        # fetch ignored packages from pacman.conf
        set ignored_pkgs (grep -Po '(?<=^IgnorePkg\s*=\s).*' /etc/pacman.conf | tr -d '\r')
        if test -n "$ignored_pkgs"
            echo (set_color red)"⚠ Skipping ignored pkgs:" $ignored_pkgs (set_color normal)
        end
    end
end