#&help:"Reloads all dotfiles"
function dotreload
    set -l hypr_real (readlink -f ~/.config/hypr)
    set -l dotfiles_dir (dirname $hypr_real)
    $dotfiles_dir/Installation/reinstall.sh $argv
end