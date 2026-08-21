#&help:"Clear + show fastfetch, same as kitty's startup sequence"
function clear --description "Clear + show fastfetch (same as kitty startup)"
    command clear
    fastfetch --percent-color-green "$theme_contrast_ansi"
    fish -c 'reload' > /dev/null 2>&1 &
end
