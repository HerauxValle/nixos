#&help: "Copes a file to clipboard"
function cpf --description 'Copy a file object to the clipboard'
    if test (count $argv) -eq 0
        # Read from stdin and create temp file in Downloads (readable by all)
        set -l tmpdir ~/Downloads
        mkdir -p $tmpdir
        set -l tmpfile (mktemp -p $tmpdir)
        chmod 644 $tmpfile
        cat > $tmpfile
        echo "file://$(realpath $tmpfile)" | wl-copy -t text/uri-list
        echo "Copied: $tmpfile" >&2
    else
        echo "file://$(realpath $argv[1])" | wl-copy -t text/uri-list
    end
end
