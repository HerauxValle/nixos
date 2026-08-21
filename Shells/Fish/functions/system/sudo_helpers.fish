#&help:"Autocompletes "sudo" when typing in "$""
function smart_sudo_bind
    if test (commandline -p) = ""
        commandline -i "sudo "
    else
        commandline -i "\$"
    end
end
bind '$' smart_sudo_bind