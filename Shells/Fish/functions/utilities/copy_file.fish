#&help: "Copes a file to clipboard"
function cpf
    echo "file://$(realpath $argv[1])" | wl-copy -t text/uri-list
end
funcsave cpf
