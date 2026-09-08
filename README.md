# OmaIce

Ice-style hidden section for the Omarchy bar: everything left of the chevron
hides, plus the system tray.

## Install

```bash
omarchy plugin add https://github.com/TerrifiedBug/omaice.git --enable
omarchy plugin disable omarchy.tray
```

The second command is not optional: OmaIce renders the system tray itself, so
leaving `omarchy.tray` enabled puts two chevrons in the bar and every tray icon
twice.

No external dependencies, no setup script, no privileged step, no background
service: the plugin is QML loaded by the running Omarchy shell.

## Usage

- Left click the chevron to reveal the hidden section; left click again to hide
  it. It also re-hides itself after `rehideSeconds` once the pointer leaves the
  bar.
- Drag a bar widget to the left of the chevron to hide it — that is the bar's
  own drag-reorder — or right click the chevron and use **Bar widgets** →
  Hide / Show. The menu stays open across as many rows as you like: the bar
  previews each one straight away and the layout is written once, when the
  menu closes.
- Right click the chevron to pin or hide individual tray icons. Pinned icons
  stay visible while the section is collapsed; hidden icons never show.
- Scriptable through IPC:

  ```bash
  qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice toggle
  qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice show
  qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice hide
  qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice opened
  ```

## Configure

```bash
# never re-hide on its own
omarchy bar set io.github.terrifiedbug.omaice rehideSeconds 0

# reveal by hovering instead of clicking
omarchy bar set io.github.terrifiedbug.omaice revealOnHover true --json

# move the divider: everything before it in the section is the hidden region
omarchy bar move io.github.terrifiedbug.omaice --section right --before omarchy.clock
```

| Setting         | Type    | Default | Effect                                                       |
| --------------- | ------- | ------- | ------------------------------------------------------------ |
| `rehideSeconds` | integer | `10`    | Seconds before an expanded section closes; `0` never closes  |
| `revealOnHover` | boolean | `false` | Reveal on hover instead of on click                          |

## How it works

The bar mounts every layout entry in a slot, and a slot with `visible: false`
reports no extent, so the section closes over it. OmaIce flips `visible` on the
slots of the entries that sit before it in its own section — on its own monitor
— which means a toggle writes nothing to `shell.json` and rebuilds nothing. The
hidden state is re-applied whenever the bar rebuilds its slots, so a drag, an
`omarchy bar move`, or a plugin being enabled does not leak a hidden widget
back into view.

On an Omarchy release that stops handing third-party widgets the live bar
object, the plugin logs one warning and degrades to a tray-only drawer; the
tray, pin, and hide behaviour is unaffected.

## Hacking on it

On omarchy 4.0.2 saving a file in `~/.config/omarchy/plugins/io.github.terrifiedbug.omaice`
logs `Local plugin changed, reloading` but the bar keeps serving the previously
compiled bar widget, so edits only show up after `omarchy-restart-shell`.
`node --test test/` covers `Model.js` without a shell at all.

## Remove

```bash
omarchy plugin remove io.github.terrifiedbug.omaice
omarchy plugin enable omarchy.tray right
```

## License

MIT — see [LICENSE](LICENSE). The tray rendering is vendored from
[omacom/omarchy](https://github.com/omacom/omarchy) under the same license.
