-- Laptop multimedia keys for volume and LCD brightness
-- Moved off bare XF86/F-keys onto CTRL+F<n> so plain F-keys reach apps/games unblocked &desc: laptop media keys, CTRL-modified to free bare F-keys
hl.bind("CTRL + F1", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),                   { repeating = true }) -- Mute toggle
hl.bind("CTRL + F2", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),                    { repeating = true }) -- Volume down
hl.bind("CTRL + F3", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),               { repeating = true }) -- Volume up
hl.bind("CTRL + F4", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),                 { repeating = true }) -- Mic mute
hl.bind("CTRL + F5", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                                { repeating = true }) -- Brightness down
hl.bind("CTRL + F6", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                                { repeating = true }) -- Brightness up

-- Requires playerctl
hl.bind("CTRL + F7", hl.dsp.exec_cmd("playerctl previous"))    -- Previous track
hl.bind("CTRL + F8", hl.dsp.exec_cmd("playerctl play-pause"))  -- Play/Pause
hl.bind("CTRL + F9", hl.dsp.exec_cmd("playerctl next"))        -- Next track
