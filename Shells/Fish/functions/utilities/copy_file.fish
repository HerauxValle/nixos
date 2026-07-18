#&help: "Copes a file to clipboard"
function cpf --description 'Copy a file object to the clipboard'
    if test (count $argv) -eq 0
        # Read from stdin and create temp file
        set -l tmpfile (mktemp)
        cat > $tmpfile
        echo "file://$(realpath $tmpfile)" | wl-copy -t text/uri-list
        echo "Copied: $tmpfile" >&2
    else
        echo "file://$(realpath $argv[1])" | wl-copy -t text/uri-list
    end
end
