#&help:"Reloads NU, BBASH, FISH and PWSH Shell"
function reload --description "Dynamically detect and reload all installed shell configs"
    echo "--- Starting Universal Reload ---"

    if test -f ~/.config/fish/config.fish
        source ~/.config/fish/config.fish
        echo "✓ [fish] Config reloaded"
    end

    set -l targets \
        "bash | bash | ~/.bashrc | source ~/.bashrc" \
        "nu   | nu   | ~/.config/nushell/config.nu | source ~/.config/nushell/config.nu" \
        "pwsh | pwsh | ~/.config/powershell/Microsoft.PowerShell_profile.ps1 | ."

    for target in $targets
        set -l parts (string split "|" $target | string trim)
        set -l name   $parts[1]
        set -l binary $parts[2]
        set -l path   (eval echo $parts[3])
        set -l cmd    $parts[4]

        if command -v $binary >/dev/null
            if test -f $path
                switch $binary
                    case bash
                        bash -ic "$cmd" 2>/dev/null
                    case nu
                        nu -c "$cmd" 2>/dev/null
                    case pwsh
                        pwsh -NoProfile -Command "$cmd '$path'" 2>/dev/null
                end
                echo "✓ [$name] Environment synced"
            else
                echo "⚡ [$name] binary found, but no config at $path"
            end
        end
    end

    set -l dotfiles_dir (dirname (readlink -f ~/.config/hypr))
    if test -f $dotfiles_dir/install.sh
        if contains -- --debug $argv
            bash $dotfiles_dir/install.sh --link
        else
            bash $dotfiles_dir/install.sh --link &>/dev/null
        end
        echo "✓ [dotfiles] Links refreshed"
    end

    echo "--- Refresh Complete ---"
end