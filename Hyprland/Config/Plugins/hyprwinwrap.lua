hl.config({
    plugin = {
        hyprwinwrap = {
            -- This plugin is mostly controlled via hyprctl commands
            -- No persistent config needed - you spawn videos with:
            -- hyprctl dispatch hyprwinwrap "<video_path>"

            -- Example usage:
            -- hyprctl dispatch hyprwinwrap "mpv --loop path/to/some.mp4"
        },
    },
})
