#&help:"Shift+Enter: open the current commandline text as a browser search"
function __search_commandline_in_browser --description "Open the current commandline buffer as a browser search"
    set -l query (string trim (commandline))
    if test -z "$query"
        commandline -f repaint
        return
    end

    # Pass raw text (not a URL) straight to the browser binary -- Chromium
    # browsers treat a non-URL argument as omnibox input and run it through
    # whatever search engine is set as default there, instead of hardcoding
    # one here. Calling $BROWSER directly (not xdg-open) also sidesteps the
    # desktop's default-handler association, which on this system resolves
    # to Tor Browser instead of $BROWSER.
    $BROWSER -- $query >/dev/null 2>&1 &
    disown

    commandline -r ''
    commandline -f repaint
end
