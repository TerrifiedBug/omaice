# OmaIce

A chevron for the Omarchy bar. Everything to its left in that section hides
behind it, bar widgets and tray icons alike. Click it when you want them back.

Omarchy's own chevron belongs to the system tray, so it only ever hides tray
icons. Bar widgets have nowhere to go, and they pile up: Spotify, a VPN
indicator, whatever else you installed last week. OmaIce takes over that spot
and treats the whole section as fair game.

![the collapsed bar, then the same bar revealed](preview.png)

Needs Omarchy 4.0.3 or later.

## Install

```bash
omarchy plugin add https://github.com/TerrifiedBug/omaice --enable --yes
omarchy plugin disable omarchy.tray
```

Both commands matter. OmaIce draws the tray itself, so leaving the built-in tray
widget enabled gives you two chevrons and every icon twice. `--enable` drops
OmaIce right after the tray, so the second command tidies away the only thing
behind your new chevron.

If the tray was already disabled, OmaIce lands at the end of the section and
everything in it starts out hidden. Click the chevron to see it all, then park
it where you want the line to be:

```bash
omarchy bar move io.github.terrifiedbug.omaice --section right --index <n>
```

Everything left of it is hidden, so `<n>` is how many widgets it swallows.

## Using it

Click to reveal, click again to collapse. It stays open until you say
otherwise, so it will not vanish while you are using something next to it. Set
`rehideSeconds` if you want it closing on its own.

To hide a widget, put it left of the chevron. That is the whole rule. Drag it
there, or right click the chevron and use the "Bar widgets" list.

That list is built for changing your mind. It stays open however many rows you
flip, and the bar previews the result as you go, so you can shuffle five widgets
and watch the section shrink before anything is written. The moves go to your
layout when you close the menu, and the bar blinks once per widget you moved.
Names in the list come from each widget's own manifest, so you get
`OmaProton VPN` instead of a guess at its id.

Some widgets you never want to see. Press "Always hide" on one and it goes,
whichever side of the chevron it was sitting on, and it stays gone when you
reveal. Its row then reads dimmed with a "Stop hiding" button that brings it
straight back to where your layout already has it. Neither direction moves
anything, so nothing jumps and the bar does not blink. When you do need one of
them, `revealAll` opens the section with those widgets included, and the next
collapse forgets them again.

Right click also pins and hides individual tray icons. A pinned icon stays put
even while the section is collapsed. A hidden one never shows up at all.

Same menu, "Behaviour" at the top: reveal on hover, a strip under the bar
instead of an inline reveal, and the indicator you want. Chevron, one dot or
three. All of them turn when the section opens, which on the dots reads as
sitting still. Every toggle applies straight away.

Inline reveal fades the widgets out of the chevron one after another, nearest
first, and collapsing runs it backwards. The strip opens in one go instead. Two
things are worse in the strip: no bar tooltips, and you cannot drag-reorder from
it. The "Bar widgets" list still moves them.

Handy on a keybind:

```bash
omarchy-shell io.github.terrifiedbug.omaice toggle
omarchy-shell io.github.terrifiedbug.omaice reveal
omarchy-shell io.github.terrifiedbug.omaice hide
omarchy-shell io.github.terrifiedbug.omaice revealAll
omarchy-shell io.github.terrifiedbug.omaice opened
```

## Settings

| Setting         | Type    | Default   | What it does                                                         |
| --------------- | ------- | --------- | -------------------------------------------------------------------- |
| `rehideSeconds` | integer | `0`       | Timeout before a revealed section closes; `0` never does              |
| `revealOnHover` | boolean | `false`   | Reveal on hover instead of on click                                  |
| `revealMode`    | string  | `inline`  | `inline` slides out beside the chevron; `row` shows a strip under it |
| `icon`          | string  | `chevron` | Indicator: `chevron`, `dot` or `dots`                                |

```bash
omarchy bar set io.github.terrifiedbug.omaice rehideSeconds 0
omarchy bar set io.github.terrifiedbug.omaice revealOnHover true --json
omarchy bar set io.github.terrifiedbug.omaice revealMode row
omarchy bar set io.github.terrifiedbug.omaice icon dots
```

## How it works

Omarchy mounts every bar entry in a slot, and an invisible slot takes up no
width, so the section closes over it. OmaIce flips that flag on the slots in
front of it. Nothing is written to disk when you reveal or collapse, and nothing
rebuilds. Only moving a widget across the chevron touches your layout.

There is no supported API for reaching those slots, so OmaIce walks the QML
scene to find them. If a future Omarchy rearranges the bar, OmaIce logs

```
omaice: own bar slot not reachable; only tray icons are hidden
```

once and carries on as a tray drawer, with an empty "Bar widgets" list.
[omacom/omarchy#10937](https://github.com/omacom/omarchy/issues/10937) is the
open request for a proper route.

One side effect worth knowing: since "hidden" means "left of the chevron",
hiding widgets from all over the bar gathers them together in front of it. That
is also why removing OmaIce leaves them where you put them.

## Uninstall

```bash
omarchy plugin remove io.github.terrifiedbug.omaice
omarchy plugin enable omarchy.tray --section right --index 0
```

Your entry leaves `shell.json`, the folder goes, and every widget it was hiding
comes back immediately. The second command puts the stock tray back; adjust the
index to place it. Your pinned and hidden tray icons belonged to OmaIce, so the
stock tray starts from its own.

`omarchy plugin disable io.github.terrifiedbug.omaice` does the same thing
temporarily, without deleting anything.

## License

MIT, see [LICENSE](LICENSE). The tray rendering, meaning icons, menus and
pinning, is vendored from
[omacom/omarchy](https://github.com/omacom/omarchy)'s own tray widget, so it
behaves like the one it replaces. [NOTICE](NOTICE) has the upstream copyright.
