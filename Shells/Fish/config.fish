set -g fish_greeting ""
set -l config_dir (dirname (status filename))
set -g fish_color_error normal

# Initialize Starship
if type -q starship
    starship init fish | source
end

# Source files
for file in $config_dir/**/*.fish
    if string match -q "*config.fish" $file
        continue
    end
    source $file
end

# Source venv cli
set -l venv_shim ~/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.fish
test -f $venv_shim; and source $venv_shim

# Theme colors: written by theme.py (run manually, live -- see
# Scripts/Reload/theme.py) straight into Dotfiles/Fastfetch/,
# copied to ~/.config/fastfetch/colors.env on rebuild, same as fastfetch's
# own config.jsonc. Reproducible/rollback-safe; needs a rebuild to change,
# not regenerated here at shell startup.
set -g theme_primary_hex "87AFD7"
set -g theme_contrast_hex "AFAFAF"
set -g theme_contrast_ansi "38;5;110"
if test -f ~/.config/fastfetch/colors.env
    for line in (cat ~/.config/fastfetch/colors.env)
        switch $line
            case 'PRIMARY_HEX=*'
                set theme_primary_hex (string sub -s 13 $line)
            case 'CONTRAST_HEX=*'
                set theme_contrast_hex (string sub -s 14 $line)
            case 'CONTRAST_ANSI=*'
                set theme_contrast_ansi (string sub -s 15 $line)
        end
    end
end

function fish_prompt
    set_color $theme_contrast_hex
    printf ' [%s] [%s] | ' (date '+%H:%M:%S') (prompt_pwd)
    # sudo -n never prompts/hangs -- succeeds only if a cached ticket already
    # lets sudo run without asking for a password right now.
    if sudo -n true 2>/dev/null
        set_color red
    else
        set_color green
    end
    printf '[•] '
    set_color $theme_primary_hex
    printf '%s ' (whoami)
    set_color $theme_contrast_hex
    printf '~> '
    set_color normal
end

if status is-interactive
    # Alt+C runs the clear function (screen clear + fresh fastfetch), taking
    # over the clear-screen role fish's default Ctrl+L binding has.
    bind alt-c 'clear; commandline -f repaint'
end

if status is-interactive
    and test "$TERM" = "xterm-kitty"
    and not set -q _fastfetch_ran
    set -gx _fastfetch_ran 1
    fastfetch --percent-color-green "$theme_contrast_ansi"
    fish -c 'reload' > /dev/null 2>&1 &
end

set -g fish_color_cancel normal
set -g fish_color_error normal
set -g fish_color_status normal
