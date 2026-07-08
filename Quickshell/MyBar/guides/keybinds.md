# Adding a New Keybind

A keybind has two parts: the UI row in Settings → Keybinds, and the IPC action that fires when the bind is pressed. Adding one requires touching 3 files in 5 spots.

---

## Where it appears in the UI

Settings → **Keybinds** tab → **OPEN** section. Each row shows a label on the left and a button on the right that opens key capture when clicked. The rows come from `_bindDefs` in BarSettings.

---

## Step-by-step

### 1. `modules/popups/BarSettings.qml` — add the UI row

Find `_bindDefs` (~line 870) and append your entry:

```qml
readonly property var _bindDefs: [
    { key: "drawer",        label: "Sidebar" },
    { key: "launcher",      label: "App Launcher" },
    { key: "controlcenter", label: "Control Center" },
    { key: "power",         label: "Power Menu" },
    { key: "settings",      label: "Settings" },
    { key: "mything",       label: "My Thing" },   // ← new
]
```

Then add a case to `_getBind` (~line 881):

```qml
case "mything": return BarConfig.bindMyThing
```

And a case to `_setBind` (~line 892):

```qml
case "mything": BarConfig.bindMyThing = value; break
```

---

### 2. `config/BarConfig.qml` — add the property, default, save, and apply

**Default** (~line 240, inside `_bindDefaults`):
```qml
"mything": "SUPER+T",
```

**Property** (~line 253, after the other bind properties):
```qml
property string bindMyThing: _parseBind("AETHERA_BIND_MYTHING") || _bindDefaults["mything"]
```

**onChange handler** (~line 262):
```qml
onBindMyThingChanged: { _schedSave(); _updateBind("mything", bindMyThing) }
```

**Save output** (~line 165, inside the save string):
```
"AETHERA_BIND_MYTHING=" + bindMyThing + "\n"
```

**applyAllBinds** (~line 293):
```qml
_updateBind("mything", bindMyThing)
```

---

### 3. `shell.qml` — add the IPC handler (~line 27)

```qml
IpcHandler {
    target: "mything"
    function onMessage(message: string) { /* your action here */ }
}
```

The IPC target name must match the `key` string used in all the steps above.

---

## Ideas for new keybinds (all built into the shell, no extra deps)

| Label | Key | Default | IPC action |
|---|---|---|---|
| Notifications | `notifications` | `SUPER+N` | `ShellState.toggleNotifications()` |
| WiFi Settings | `wifi` | `SUPER+W` | `BarConfig.togglePopup("wifi", "")` |
| Bluetooth | `bluetooth` | `SUPER+SHIFT+B` | `BarConfig.togglePopup("bluetooth", "")` |
| Workspace Menu | `workspacemenu` | `SUPER+SHIFT+W` | `BarConfig.togglePopup("workspacemenu", "")` |

`toggleNotifications` is the most useful one missing — it's already on the bar icon but has no keyboard shortcut.
