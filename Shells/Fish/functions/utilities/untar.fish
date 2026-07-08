#&help:""Untar" files easily"
function untar
    set -l target $argv[1]
    if test -f "$target"
        set -l dir (dirname (realpath $target))
        # Removed -z so it handles .xz, .gz, and .bz2 automatically
        tar -xf $target -C $dir
        if contains -- "-r" $argv
            rm $target
        end
    else
        echo "Error: File $target not found."
    end
end