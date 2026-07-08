#&help:"resolve a dirs/files entire path"
function getpath --description 'Get the full path of a file or directory'
    # Check for the --root flag
    set -l use_root false
    set -l targets ()

    for arg in $argv
        if test "$arg" = "--root"
            set use_root true
        else
            set -a targets $arg
        end
    end

    # If no file/dir provided, default to current directory
    if test (count $targets) -eq 0
        set targets .
    end

    for item in $targets
        # Resolve the absolute path natively
        set -l full_path (realpath $item)
        
        if test "$use_root" = "true"
            echo $full_path
        else
            # Replace /home/username with ~ for standard behavior
            string replace -r "^$HOME" '~' $full_path
        end
    end
end

# Create the gp shortcut/alias pointing to the function
alias gp=getpath