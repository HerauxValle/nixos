#&help: "Copes a file to clipboard"
function cpf --description 'Copy a file object to the clipboard'
    if test (count $argv) -eq 0
        echo "Usage: cpf <file>"
        return 1
    end
    echo "file://$(realpath $argv[1])" | wl-copy -t text/uri-list
end
