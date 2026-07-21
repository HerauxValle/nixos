<!-- &desc: "usage: build, load, configure the toggle bind" -->
# canvas

ComfyUI-style infinite pan/zoom canvas for Hyprland. Windows keep their
normal positions on an infinite plane; this plugin moves a camera over it.

Design rationale, verified function signatures, and known limitations: see
[DESIGN.md](./DESIGN.md).

## Controls

- **Meta+Shift+C** -- toggle canvas mode on/off
- **Meta+Shift+Scroll** (while active) -- zoom in/out, anchored at the cursor
- **Meta+Shift+Right-Drag** (while active) -- pan, anywhere on screen

## Build

Requires Hyprland's development headers (`pkg-config hyprland` must resolve)
matching the Hyprland version actually running -- this plugin hooks internal
functions by name/signature, so a mismatched header version can silently
misbehave rather than fail to compile. See DESIGN.md's "Known limitations."

```bash
make
make install   # hyprctl plugin load $PWD/canvas.so
```

To load automatically, add to `hyprland.conf`:

```
plugin = /home/herauxvalle/Dotfiles/Hyprland/plugins/canvas/canvas.so
bind = SUPER SHIFT, C, canvas:toggle
```

The `bind` line is required -- the plugin only registers the `canvas:toggle`
dispatcher, it does not add the keybind itself (see DESIGN.md, "Rejected
alternatives," for why).

```bash
make reload   # iterate: unload + rebuild + reload, bypassing dlopen cache
make unload
```
