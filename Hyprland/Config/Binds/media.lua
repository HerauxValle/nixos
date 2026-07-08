-- Audio control
hl.bind(mainMod .. " + ALT + up",    hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind(mainMod .. " + ALT + down",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),     { repeating = true })
hl.bind(mainMod .. " + ALT + left",  hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),    { repeating = true })
hl.bind(mainMod .. " + ALT + right", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0"),         { repeating = true })
