# OmaIce

A chevron for the Omarchy bar that hides everything to its left, bar widgets and
tray icons alike. Click it when you want them back.

Omarchy already ships a chevron, but it belongs to the system tray and only ever
hides tray icons. Bar widgets have nowhere to go: WhatsApp, Spotify, a VPN
indicator, the half-dozen things that accumulate on the right. OmaIce replaces
that chevron with one that treats the whole section as fair game.

![the collapsed bar, then the same bar revealed](preview.png)

## Install

```bash
omarchy plugin add https://github.com/TerrifiedBug/omaice.git --enable
omarchy plugin disable omarchy.tray
```

That's the whole thing. Run the two commands in that order and you're done. No
setup script, no config file to edit, nothing to restart.

Both commands matter. OmaIce draws the system tray itself, so the built-in tray
widget has to step aside; leave it enabled and you get two chevrons and every
tray icon twice. Order matters too, pleasantly: `--enable` drops OmaIce directly
after the tray, so the only thing behind your new chevron is the old tray
widget. Nothing of yours disappears, and the second command tidies away the
leftover.

If you install with the tray already disabled, OmaIce lands at the end of the
section instead, which means everything in it starts out hidden. Nothing is
lost; click the chevron to see it all, then park the chevron where you actually
want the boundary:

```bash
omarchy bar move io.github.terrifiedbug.omaice --section right --index 0
```

No external dependencies, no privileged step, no background service. The plugin
is QML loaded into the Omarchy shell you're already running.

## Using it

Click the chevron to reveal the hidden section, click again to collapse it. It
also collapses on its own ten seconds after your pointer leaves the bar. Set
`rehideSeconds` to `0` if you'd rather it stayed put.

To hide a widget, put it to the left of the chevron. That's the entire rule.
Drag it there with Omarchy's own bar drag-reorder, or right click the chevron
and use the "Bar widgets" list.

The list is built for changing your mind: it stays open however many rows you
toggle, and the bar shows you the result as you go, so you can shuffle five
widgets and watch the section shrink before anything is saved. The moves are
written to your layout when you close the menu, one `omarchy bar move` per
widget you changed, so the bar does blink once per change as it re-lays out.
Nothing is written while the menu is open.

Right click also pins and hides individual tray icons. A pinned icon stays in
the bar even while the section is collapsed; a hidden one never appears at all.
Everything else lives behind the chevron.

If you prefer hover, `revealOnHover true` reveals the section when your pointer
reaches the chevron and collapses it shortly after the pointer leaves the bar.

It is scriptable too, if you want it on a keybind:

```bash
qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice toggle
qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice reveal
qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice hide
qs ipc -p "$OMARCHY_PATH/shell" call io.github.terrifiedbug.omaice opened
```

## Settings

| Setting         | Type    | Default | What it does                                                |
| --------------- | ------- | ------- | ----------------------------------------------------------- |
| `rehideSeconds` | integer | `10`    | Seconds before a revealed section collapses; `0` never does  |
| `revealOnHover` | boolean | `false` | Reveal on hover instead of on click                          |

```bash
omarchy bar set io.github.terrifiedbug.omaice rehideSeconds 0
omarchy bar set io.github.terrifiedbug.omaice revealOnHover true --json
```

## How it works

Omarchy mounts every bar entry in a slot, and a slot marked invisible reports no
width, so the section simply closes over it. OmaIce flips that flag on the slots
sitting before it in its own section, on its own monitor, which means collapsing
and revealing writes nothing to disk and rebuilds nothing. Only *moving* a
widget across the chevron touches your layout.

The state is re-applied whenever the bar rebuilds its slots, so dragging a
widget, running `omarchy bar move`, or enabling another plugin won't leak a
hidden widget back into view.

Because "hidden" means "left of the chevron", the hidden set is always a
contiguous run at the start of the section. Hiding widgets that are scattered
through the bar gathers them together in front of the chevron. That is the
mechanism showing through, and it's why removing OmaIce leaves them where you
put them rather than springing them back to their old spots.

## Compatibility

On omarchy 4.0.3 OmaIce is a tray drawer. That release moved third-party bar
widgets onto a capability-scoped bar facade (`Bar.pluginBarApiFor`) which does
not expose the module slots, so nothing can conceal a sibling widget any more.
OmaIce logs

```
omaice: bar.moduleSlots unavailable; only tray icons are hidden
```

exactly once and carries on. Chevron, reveal, auto-rehide and tray pin/hide all
work; the "Bar widgets" list is empty, and widgets left of the chevron stay
visible. Verified on 4.0.3 with quickshell 0.3.1.

Full behaviour, bar widgets included, needs omarchy 4.0.2-1, where the bar
hands a mounted widget the live bar object. Getting it back on 4.0.3 needs a
supported way to conceal a sibling slot, and that capability has to come from
the host; a plugin cannot grant it to itself.

## Uninstall

```bash
omarchy plugin remove io.github.terrifiedbug.omaice
omarchy plugin enable omarchy.tray --section right --index 0
```

Removal is clean: the entry leaves your `shell.json`, the plugin folder is
deleted, and every widget it was hiding becomes visible again immediately. The
second command puts the stock tray back where it was. Your pinned and hidden
tray-icon choices belonged to OmaIce, so the stock tray starts from its own.

`omarchy plugin disable io.github.terrifiedbug.omaice` does the same thing
temporarily, without deleting anything.

## Hacking on it

Clone it, `omarchy plugin add "file://$PWD" --enable`, and edit the installed
copy in `~/.config/omarchy/plugins/io.github.terrifiedbug.omaice`.

On omarchy 4.0.2 saving a file there logs `Local plugin changed, reloading` but
the bar keeps serving the bar widget it already compiled, so changes only show
up after `omarchy-restart-shell`. The pure logic in `Model.js` is testable
without a shell at all: `node --test test/`.

## Credits

The tray rendering, meaning icons, menus and pinning, is vendored from
[omacom/omarchy](https://github.com/omacom/omarchy)'s own tray widget, so it
behaves exactly like the one it replaces. See [NOTICE](NOTICE) for the upstream
copyright.

## License

MIT, see [LICENSE](LICENSE), and [NOTICE](NOTICE) for the vendored parts (also
MIT).
