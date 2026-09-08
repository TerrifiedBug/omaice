# OmaIce (archived, does not work on Omarchy 4.0.3)

Do not install this. On Omarchy 4.0.3 and later, OmaIce cannot do the one thing
it exists for, and there is no version of the plugin that can.

It was a chevron for the Omarchy bar that hid everything to its left, bar
widgets and tray icons alike. The stock chevron belongs to the system tray and
only ever hides tray icons, so bar widgets, WhatsApp, Spotify, a VPN indicator
and the half-dozen things that accumulate on the right, had nowhere to go.
OmaIce replaced that chevron with one that treated the whole section as fair
game.

## Why it stopped working

Hiding a sibling widget needed the bar's module slots: a slot marked invisible
reports no width, so the section closes over it. Omarchy 4.0.2 handed a mounted
third-party widget the live bar object, and the slots came with it.

4.0.3 moved third-party bar widgets onto a capability-scoped facade,
`Bar.pluginBarApiFor`, which exposes colours, geometry, tooltips, popouts and
the plugin's own widgets. The module slots are not on it, and `moduleWidgets()`
answers only for the calling plugin's own module. Nothing a plugin can reach
conceals another plugin's widget.

That boundary is deliberate and it is the right call: a bar widget being able
to hide, or read, its neighbours is exactly the kind of access a plugin should
not have by default. Restoring OmaIce would need the host to offer a narrow
capability of its own, something like "conceal and reveal the slots before me
on this bar surface". Until Omarchy offers that, this plugin has no path.

On 4.0.3 it logs

```
omaice: bar.moduleSlots unavailable; only tray icons are hidden
```

once and runs as a tray drawer. The chevron, reveal, auto-rehide and tray
pin/hide still work, and the "Bar widgets" list is empty. That is a fraction of
the plugin, and not what anyone installs it for.

## If you have it installed

```bash
omarchy plugin remove io.github.terrifiedbug.omaice
omarchy plugin enable omarchy.tray --section right --index 0
```

The second command matters. OmaIce drew the system tray itself, so the install
instructions had you disable the stock tray; without this you are left with no
tray at all. Adjust the index to put the tray where you want it. Your pinned
and hidden tray-icon choices belonged to OmaIce, so the stock tray starts from
its own.

## What is left here

The repository is archived and read only. The code is MIT and still readable if
the slot-hiding trick is useful to you, and `Model.js` is Qt-free with tests
under `test/`. The tray rendering is vendored from
[omacom/omarchy](https://github.com/omacom/omarchy)'s own tray widget; see
[NOTICE](NOTICE) for the upstream copyright.

## License

MIT, see [LICENSE](LICENSE), and [NOTICE](NOTICE) for the vendored parts (also
MIT).
