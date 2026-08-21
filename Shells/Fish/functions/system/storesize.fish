#&help:"Nix store size overview + biggest paths"
function storesize --description "Current generation closure size, total store size, and the biggest store paths"
    set_color cyan
    echo "Current generation (closure):"
    set_color normal
    du -shc (nix-store -qR /run/current-system) 2>/dev/null | tail -1 | string replace -r '\s+total$' ''

    echo
    set_color cyan
    echo "Total /nix/store:"
    set_color normal
    du -sh /nix/store 2>/dev/null

    echo
    set_color cyan
    echo "Top 5 largest store paths:"
    set_color normal
    for line in (du -sh /nix/store/*/ 2>/dev/null | sort -rh | head -5)
        set -l parts (string split -m1 \t -- $line)
        set_color yellow
        echo -n $parts[1]
        set_color normal
        echo "  "$parts[2]
        for inner in (du -sh $parts[2]/* 2>/dev/null | sort -rh | head -3)
            set -l iparts (string split -m1 \t -- $inner)
            echo "    "$iparts[1]"  "(basename $iparts[2])
        end
    end
end
