#&help:"Shift+Enter: open the commandline buffer in the browser -- URL navigates, anything else searches via the browser's own default search engine"
function __search_commandline_in_browser --description "Omnibox-style Shift+Enter: navigate URLs, search everything else"
    set -l input (string trim (commandline))
    if test -z "$input"
        commandline -f repaint
        return
    end

    set -l target

    if string match -qr '^[a-zA-Z][a-zA-Z0-9+.-]*://' -- $input
        # Already has a scheme (http://, ftp://, file://, ...).
        set target $input
    else if string match -qr '^(localhost|(\d{1,3}\.){3}\d{1,3})(:\d+)?(/.*)?$' -- $input
        # localhost or a bare IPv4, with an optional port/path.
        set target "http://$input"
    else if string match -qr '^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}(:\d+)?(/.*)?$' -- $input
        # Looks like a bare domain (has a dot + TLD-shaped ending, no spaces).
        set target "https://$input"
    end

    if test -z "$target"
        # Not URL-shaped -> search. Find whatever search engine the browser
        # itself has configured as default (Chromium-family profile store),
        # instead of hardcoding one here.
        set -l engine_url (__default_search_engine_url)
        if test -n "$engine_url"
            set -l encoded (string escape --style=url -- $input | string replace -a '%20' '+')
            set target (string replace '{searchTerms}' $encoded -- $engine_url)
        end
    end

    if test -n "$target"
        $BROWSER -- $target >/dev/null 2>&1 &
    else
        # Couldn't resolve a default search engine (e.g. non-Chromium
        # browser) -- hand the raw text to the browser and let it apply its
        # own CLI-arg handling.
        $BROWSER -- $input >/dev/null 2>&1 &
    end
    disown

    commandline -r ''
    commandline -f repaint
end

function __default_search_engine_url --description "Read the default browser's own configured default search engine URL template"
    if not type -q jq
        return
    end

    set -l browser_name (path basename $BROWSER)
    set -l config_dir
    for d in ~/.config/*/
        set -l base (path basename $d)
        if string match -qi "*$browser_name*" -- $base; or string match -qi "*$base*" -- $browser_name
            set config_dir (string trim -r -c / -- $d)
            break
        end
    end
    if test -z "$config_dir"
        return
    end

    set -l profile Default
    if test -f "$config_dir/Local State"
        set -l last (jq -r '.profile.last_used // empty' "$config_dir/Local State" 2>/dev/null)
        test -n "$last"; and set profile $last
    end

    for p in $profile Default
        set -l prefs "$config_dir/$p/Preferences"
        if test -f "$prefs"
            set -l url (jq -r '.default_search_provider_data.template_url_data.url // empty' "$prefs" 2>/dev/null)
            if test -n "$url"
                echo $url
                return
            end
        end
    end
end
