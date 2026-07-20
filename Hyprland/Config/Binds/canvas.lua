-- canvas plugin: infinite canvas per workspace (see Hyprland/plugins/canvas/DESIGN.md)
-- Hold mainMod + SHIFT for every canvas action, kept off plain mainMod
-- entirely so nothing here can collide with mainMod's existing window
-- drag/resize mouse binds (mouse:272/273) in windows.lua.

-- Toggle canvas mode for the workspace under the cursor
hl.bind(mainMod .. " + SHIFT + C", function() hl.plugin.canvas.toggle() end)

-- Reset zoom/pan back to 1:1
hl.bind(mainMod .. " + SHIFT + R", function() hl.plugin.canvas.reset() end)

-- Keyboard pan (repeats while held)
hl.bind(mainMod .. " + SHIFT + up",    function() hl.plugin.canvas.pan("up") end,    { repeating = true })
hl.bind(mainMod .. " + SHIFT + down",  function() hl.plugin.canvas.pan("down") end,  { repeating = true })
hl.bind(mainMod .. " + SHIFT + left",  function() hl.plugin.canvas.pan("left") end,  { repeating = true })
hl.bind(mainMod .. " + SHIFT + right", function() hl.plugin.canvas.pan("right") end, { repeating = true })

-- Scroll to zoom (wheel up = in, wheel down = out)
hl.bind(mainMod .. " + SHIFT + mouse_up",   function() hl.plugin.canvas.zoom("in") end)
hl.bind(mainMod .. " + SHIFT + mouse_down", function() hl.plugin.canvas.zoom("out") end)

-- Hold + right-click-drag to pan
hl.bind(mainMod .. " + SHIFT + mouse:273", function() hl.plugin.canvas.panDrag() end, { mouse = true })
