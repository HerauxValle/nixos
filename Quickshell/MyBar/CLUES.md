# MyBar — Persistent Dev Rules

## Scrollbars
- Scrollbar Rectangle must be a **sibling** of the Flickable, never a child. If it's a child it scrolls with content and appears static.
- Correct formula (copy exactly):
  ```qml
  readonly property real _r: BarConfig.sp(14)   // match container's corner radius
  readonly property real _thumbH: flick.visibleArea.heightRatio * flick.height
  y: Math.max(flick.y, Math.min(flick.y + flick.height - _thumbH - _r,
              flick.y + flick.visibleArea.yPosition * flick.height))
  width: BarConfig.sp(3); height: _thumbH
  radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.5; z: 5
  ```
- `_r` inset keeps thumb away from rounded bottom corner of the container.
- Flickable must have `bottomMargin: BarConfig.sp(14)` (matching the container's corner radius) so content never bleeds through the rounded bottom corner. Use explicit anchors: `anchors { fill: parent; bottomMargin: BarConfig.sp(14) }` or `anchors { top: hdr.bottom; ...; bottom: parent.bottom; bottomMargin: BarConfig.sp(14) }`.
- Do NOT use `StopAtBounds` — it kills the elastic bounce feel. The clamped formula already prevents the thumb from going out of bounds during overscroll.
- `boundsBehavior` only exists on Flickable. Never put it on Item, Rectangle, or inline components.

## Keyboard focus in layer-shell windows
- `WlrLayershell.keyboardFocus` must be `OnDemand` (not `None`) for any window that needs key events (ESC, Enter, etc.).
- The drawer uses `None` by default. When a text input inside it becomes active, switch to `OnDemand` via a forwarding property on the PanelWindow (`_taskInputActive`), then switch back to `None` on dismiss.
- After a Loader loads a new item that needs key input, call `item.forceActiveFocus()` in `onLoaded`, and again via `Qt.callLater` in `Connections { onCurrentPopupChanged }` when the popup becomes active.

## Per-screen popup isolation
- `BarConfig.currentPopupScreen` tracks which screen owns the open popup.
- All `togglePopup` / `openBarSettings` calls must pass `barScreenName`.
- `myPopupActive` checks both `currentPopup !== ""` AND `currentPopupScreen === barWindow.screenName`.
- `barScreenName` is set on Loader items via `onLoaded`.

## Colors / opacity consistency
- All popup/drawer backgrounds: `Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)`.
- Never use `Colors.popupBg` as a background — it has a hardcoded dark tint that breaks consistency.

## LSP false positives vs real errors
- `pragma ComponentBehavior: Bound` causes many LSP warnings. Most are false positives — but **unqualified access warnings inside Repeater delegates are real and will cause runtime failures**. Always qualify delegate property access using the delegate's `id` (e.g. `appRow.modelData`, `appRow.index`, `appRow.isSelected`). Fix these. Ignore everything else (missing-property on Flickable, Timer, Animation members, etc.).

## Burger icon
- Do NOT modify the burger icon toggle in `BarContent.qml` left section (drawer toggle).

## Scaling
- Use `BarConfig.sp(n)` for ALL pixel values in popups, drawer, and notifications — positions, sizes, margins, radii, gaps. Reference resolution is 1440p. Never use hardcoded px values.

## Technology choices
- Need a widget? → QML
- Need a service? → QML or JS
- Need to talk to Linux internals or do heavy work? → C++
- Need build/install tooling? → Python/Shell
- When rewriting a file entirely (not just line edits), reconsider the language — most things here are QML, but pick the right tool for the job.
- **Scaling rule**: if the work stays small and fixed (one file, one command, a handful of items) QML/Shell is fine. If it scales with data size (scanning directories, parsing many files, processing large output) → use C++ immediately, not shell scripts. Shell scanning 100+ .desktop files is the canonical example of what NOT to do in QML.

## Project layout
```
MyBar/
├── main.sh              ← entry point: --launch / --compile / --install / --uninstall
├── scripts/             ← shell scripts, grouped by purpose in subfolders
│   ├── launch/          (launch.sh)
│   └── build/           (compile.sh, install.sh, uninstall.sh)
├── source/              ← C++ sources, one subfolder per tool
│   └── appscanner/
├── binary/              ← compiled binaries, flat (names must be unique), gitignored
├── modules/             ← QML UI modules
├── config/              ← QML config singletons
├── services/            ← QML service singletons
└── themes/              ← .env theme files
```
- `scripts/` subfolders group by purpose, never dump scripts flat at the top level.
- `source/` subfolders group by tool — each C++ tool gets its own subfolder.
- `binary/` stays flat; binary names must be unique across all tools.
- New C++ tool: add `source/toolname/toolname.cpp`, one line in `scripts/build/compile.sh`, output to `binary/toolname`.

## Install / uninstall contract
- After uninstall, system state must be identical to before install. Never leave behind group memberships, config files, or side effects that weren't there before.
- `~/.config/mybar/state/pkgs.json` is created by install.sh and records which packages were installed by Aethera (vs already present). Uninstall reads it and only removes what was recorded. Never created manually by the user.

## Persistence
- All user-settable state saves to `~/.config/mybar/theme.env` via `BarConfig._schedSave()`.
- `launch.sh` sources that file on startup — env vars flow in as `Quickshell.env("AETHERA_*")`.
- New persisted values need: init property reading env var, user-facing property defaulting to init, `onChanged: _schedSave()`, and a line in `_saveTimer.onTriggered`.

## User-overridable variables
- Any hardcoded value a user might want to change MUST be a `AETHERA_*` env var with a QML fallback: `parseInt(Quickshell.env("AETHERA_FOO") || "default")`.
- `launch.sh` sources `~/.config/mybar/custom/*.env` last — anything there wins over theme and saved state.
- All variables are documented in `guides/variables.md`. Update it whenever a new var is added.
- `variables.env.example` in the repo root is the copy-paste template for users. Keep it in sync with `guides/variables.md`.
