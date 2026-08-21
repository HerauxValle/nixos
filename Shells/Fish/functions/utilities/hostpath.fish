#&help:"Serve a file or directory over HTTP for as long as the terminal stays attached"
function hostPath --description "Quick HTTP file/dir server (LAN accessible, dies with the terminal)"
    set -l options 'p/path=' 'P/port=' 'H/host='
    argparse $options -- $argv
    or return 1

    set -l host 0.0.0.0
    set -l port 9876
    set -l path (pwd)

    if set -q _flag_host
        set host $_flag_host
    end

    if set -q _flag_port
        set port $_flag_port
    end

    if set -q _flag_path
        set path $_flag_path
    end

    if not test -e "$path"
        set_color red
        echo "Error: Path '$path' does not exist." >&2
        set_color normal
        return 1
    end

    set -l serve_dir
    set -l serve_file
    if test -f "$path"
        set serve_dir (dirname "$path")
        set serve_file (basename "$path")
    else
        set serve_dir "$path"
    end

    # Real LAN IP for devices to connect to; 0.0.0.0 only makes sense server-side
    set -l lan_ip $host
    if test "$host" = "0.0.0.0"
        set lan_ip (ip route get 1.1.1.1 2>/dev/null | string match -r 'src (\S+)' -g)
        if test -z "$lan_ip"
            set lan_ip 127.0.0.1
        end
    end

    set_color cyan
    echo -n "Serving "
    set_color yellow
    if set -q serve_file
        echo -n "$serve_file"
    else
        echo -n "$serve_dir"
    end
    set_color cyan
    echo " (Ctrl+C to stop, closes with this terminal)"
    set_color normal

    echo -n "  "
    set_color green
    if set -q serve_file
        echo -n "http://$lan_ip:$port/$serve_file"
    else
        echo -n "http://$lan_ip:$port/"
    end
    set_color normal
    echo "  <- open this on other devices"

    if test "$lan_ip" != "127.0.0.1"
        echo -n "  "
        set_color blue
        if set -q serve_file
            echo -n "http://127.0.0.1:$port/$serve_file"
        else
            echo -n "http://127.0.0.1:$port/"
        end
        set_color normal
        echo "  <- local"
    end
    echo

    python3 -m http.server $port --bind $host --directory "$serve_dir"
end
