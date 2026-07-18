#&help: "Copies a file object to the clipboard"
function cpf --description 'Copy a file object to the clipboard'
    if test (count $argv) -eq 0
        # Read stdin, write to temp file, copy file to clipboard
        set -l tmpdir ~/Downloads
        mkdir -p $tmpdir
        set -l tmpfile (mktemp -p $tmpdir)
        cat > $tmpfile
        chmod 644 $tmpfile
        echo -n "file://"(realpath $tmpfile) | wl-copy -t text/uri-list
        echo "Copied: $tmpfile" >&2
    else
        # Copy existing file to clipboard
        echo -n "file://"(realpath $argv[1]) | wl-copy -t text/uri-list
    end
end
