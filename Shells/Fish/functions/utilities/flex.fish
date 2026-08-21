#&help:"Clear + show maxed-out fake fastfetch stats"
function fetch-flex --description "Clear + show maxed-out fake fastfetch stats"
    command clear
    fastfetch --config ~/.config/fastfetch/config-flex.jsonc --percent-color-green "$theme_contrast_ansi"
end
