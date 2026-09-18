import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel
import "Model.js" as Model

// Tray rendering vendored from omacom/omarchy 4.0.2 shell/plugins/bar/widgets/Tray.qml (MIT); the drawer became an Ice-style hidden section.
//
// Ice-style divider: the chevron hides every bar entry placed before it in its
// own section, plus the tray icons in the drawer bucket. Hiding is done by
// flipping `visible` on the host's ModuleSlots, reached by walking the QML
// scene from this item to the slot that mounts it and to the slots beside it.
// Omarchy 4.0.3 hands a plugin widget a bar facade with no sibling access, and
// upstream documents the parent hierarchy of the scene as the thing the facade
// cannot isolate a visual child from, so the scene is the only route. Nothing
// is written to disk and nothing rebuilds on a toggle; the state is re-applied
// whenever the bar rebuilds its slots. Absorbing the tray is deliberate: two
// chevrons (one per plugin) would each own half the hidden items.
BarWidget {
  id: root
  moduleName: "io.github.terrifiedbug.omaice"

  property bool expanded: false
  // Peek state for the always-hidden set: set by the revealAll IPC only, and
  // cleared by any collapse, so a plain reveal never leaks those widgets back.
  property bool revealAll: false
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property string icon: Model.normalizeIcon(setting("icon", "chevron"))
  // Widgets that stay hidden whichever side of the chevron they sit on. Not in
  // the manifest schema: like pinned/hidden it is a list the host form cannot
  // produce, and persistSettings rebuilds the entry so the key survives.
  readonly property var alwaysHiddenIds: Model.normalizeIdList(settings.alwaysHidden)
  // chevron: nf-fa-chevron_left, dots: nf-fa-ellipsis_h. A plain bullet
  // matches one ellipsis dot; every Nerd Font circle draws much bigger.
  readonly property string iconGlyph: icon === "dot"
    ? "\u2022"
    : icon === "dots"
      ? "\uf141"
      : "\uf053"
  // 0 by default: a click-mode reveal closes when you click off it, not on a
  // clock. Set it if you want a timeout as well.
  readonly property int rehideSeconds: Model.normalizeRehideSeconds(setting("rehideSeconds", 0), 0)
  readonly property bool revealOnHover: setting("revealOnHover", false) === true
  readonly property string revealMode: Model.normalizeRevealMode(setting("revealMode", "inline"))
  // Row reveal needs a horizontal bar; a vertical bar has no "row below".
  readonly property bool rowMode: revealMode === "row" && !root.vertical
  // Any popout on the bar holds the section open. A widget's popup places
  // itself against the window it lives in, so collapsing while one is up
  // sends the widget back to the bar and takes its panel with it. Identity is
  // no help here: the facade hands a plugin `foreignPopoutMarker` instead of
  // whichever widget actually owns the popout (Bar.qml syncPluginBarApiObjects),
  // so anything open at all is treated as ours to wait for.
  readonly property bool barPopoutOpen: root.bar ? !!root.bar.activePopout : false
  readonly property bool popupOpen: managePopupOpen || trayMenuOpen || barPopoutOpen
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: 0
  readonly property int trayJoinGap: 0
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0
  // Match Waybar's group/tray-expander drawer transition-duration.
  readonly property int animationDuration: 600
  property real revealProgress: expanded ? 1 : 0
  // Row mode draws the hidden set in its own strip, so the chevron block must
  // stop reserving inline drawer width.
  readonly property real revealExtent: rowMode ? 0 : drawerExtent * revealProgress

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    trayMenuFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item || !item.menu) {
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to IconImage; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  // updateEntryInline rewrites the whole entry from what it is handed, so
  // rebuild it off the live settings and overlay the changed keys: a bare
  // {id, pinned, hidden} would drop rehideSeconds and revealMode on the first
  // pin. The host treats a settings-only write as an in-place patch (no widget
  // rebuild), so the manage popup survives it.
  function persistSettings(changes) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var changed in changes) entry[changed] = changes[changed]
    root.settings = entry
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function togglePin(iid) {
    var next = Model.toggleBucket(root.pinnedIds, root.hiddenIds, iid, "pinned")
    persistSettings({ pinned: next.pinned, hidden: next.hidden })
  }

  function toggleHide(iid) {
    var next = Model.toggleBucket(root.pinnedIds, root.hiddenIds, iid, "hidden")
    persistSettings({ pinned: next.pinned, hidden: next.hidden })
  }

  // ---- Ice divider. The hidden set is the host's ModuleSlots for the entries
  //      that sit before this widget in its own section, on this widget's own
  //      bar window. A slot with visible: false reports no extent and the
  //      section Row skips it, so the bar closes over the gap.
  property var managedSlots: []
  // Where the managed slots go back to. Cached because unregistering the
  // widget clears the host ModuleSlot's activeItem before this item is
  // destroyed, so ownSlot, sectionRow and its region are all gone by the time
  // releaseHidden runs.
  property var managedSectionRow: null
  property var managedLayoutOrder: []
  // Bumped whenever the section's slots may have been rebuilt, so the
  // sectionWidgets binding has something to depend on: the slot list comes
  // from a function call, which QML cannot track.
  property int slotRevision: 0

  // The host mounts a registered widget as registryLoader.item inside its
  // ModuleSlot, so the slot is a couple of parents up. Matched by identity,
  // not by moduleName: the same widget id is mounted once per monitor.
  readonly property var ownSlot: {
    var item = root.parent
    for (var depth = 0; item && depth < 8; depth++) {
      if ("activeItem" in item && item.activeItem === root) return item
      item = item.parent
    }
    return null
  }

  // The Row (or Column on a vertical bar) that lays out this section's slots.
  readonly property var sectionRow: ownSlot ? ownSlot.parent : null

  // Pointer over the ice section: the chevron's own slot, any revealed
  // sibling, or the row strip. The facade has no barHovered, so this is
  // narrower than it was on purpose - the rehide countdown pauses only while
  // the user is on the section itself.
  readonly property bool sectionHovered: {
    if (ownSlot && ownSlot.hovered) return true
    if (stripHover.hovered) return true
    // In row mode the strip card's own handler already covers every revealed
    // widget, so the per-slot check below adds nothing but a way for the
    // section to stay open after the pointer has gone: a slot re-parented into
    // another window can keep reporting hovered from the window it left.
    if (root.rowMode) return false
    var slots = root.managedSlots
    for (var i = 0; i < slots.length; i++) if (slots[i] && slots[i].hovered) return true
    return false
  }

  // Popup Hide/Show only flips a local override. A layout write rebuilds this
  // widget and would take the popup down with it on every click, so the rows
  // stage instead: the section previews the staged result immediately and the
  // moves are committed as one shell command when the popup closes.
  property var stagedWidgets: ({})

  // The slots a reveal actually shows: the managed set minus the always-hidden
  // ones, unless the revealAll peek is on. Every input is a property, so the
  // binding tracks them.
  readonly property var revealableSlots: managedSlots.filter(function(slot) {
    return slot && (!isAlwaysHidden(slot) || root.revealAll)
  })

  // Entries sharing this widget's section, split by the divider, for the
  // manage popup. Slot order is layout order, so the slots are the layout.
  readonly property var sectionWidgets: {
    var revision = root.slotRevision
    var staged = root.stagedWidgets
    var always = root.alwaysHiddenIds
    var slots = sectionSlots()
    var divider = slots.indexOf(ownSlot)
    if (divider === -1) return []
    var rows = []
    for (var i = 0; i < slots.length; i++) {
      if (i === divider) continue
      rows.push(widgetRow(slots[i], i < divider))
    }
    return rows
  }

  function expand() { expanded = true }

  // Any collapse drops the peek, so the next plain reveal leaves the
  // always-hidden widgets where they are.
  function collapse() {
    expanded = false
    revealAll = false
  }

  function toggle() {
    if (expanded) collapse()
    else expand()
  }

  // Sibling ModuleSlots of this section on this monitor, in layout order. A
  // slot is found under the section Row or, in row mode, under the strip; the
  // layout config is the order, since re-parenting appends. The Repeater is
  // also a child of the Row; the duck-typed test skips it.
  function sectionSlots() {
    if (!sectionRow) return []
    var found = []
    collectSlots(sectionRow.children, found)
    collectSlots(stripFlow.children, found)
    var order = layoutOrder()
    found.sort(function(a, b) { return rank(a, order) - rank(b, order) })
    return found
  }

  function collectSlots(kids, out) {
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (kid && "activeItem" in kid && "region" in kid && "moduleName" in kid) out.push(kid)
    }
  }

  // Entry ids of this section from the facade's layout copy.
  function layoutOrder() {
    var region = ownSlot ? ownSlot.region : ""
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig[region] : null
    var ids = []
    if (Array.isArray(layout)) for (var i = 0; i < layout.length; i++) ids.push(TrayModel.entryId(layout[i]))
    return ids
  }

  // Unknown ids (layout copy momentarily stale) sort after known ones, stable.
  function rank(slot, order) {
    var index = order.indexOf(slot.moduleName)
    return index === -1 ? order.length : index
  }

  function isAlwaysHidden(slot) {
    return root.alwaysHiddenIds.indexOf(slot.moduleName) !== -1
  }

  // The positional hidden set plus every always-hidden widget, whichever side
  // of the chevron it sits on. One pass over the slots, so the result keeps
  // layout order.
  function hiddenSlots() {
    var slots = sectionSlots()
    var divider = slots.indexOf(ownSlot)
    if (divider === -1) return []
    var result = []
    for (var i = 0; i < slots.length; i++) {
      if (i === divider) continue
      if (stagedHidden(slots[i].moduleName, i < divider) || isAlwaysHidden(slots[i])) result.push(slots[i])
    }
    return result
  }

  // Re-apply after the current pass of bindings and slot registrations, so a
  // burst of slot registrations costs one pass. An owned one-shot Timer, not
  // Qt.callLater: destroying this widget cancels the timer, while a queued
  // closure outlives the object and runs against its corpse.
  function reapplySoon() { reapplyTimer.restart() }

  // Slots that changed window in the last pass and are waiting to be shown
  // again; see repaintTimer.
  property var repaintQueue: []

  // Idempotent: releases slots that left the hidden set before applying the
  // current one, so a widget dragged past the chevron is never left invisible.
  // In row mode a hidden slot lives in the strip whether the section is open
  // or not: moving one between windows rebuilds its scene graph and re-parents
  // the popups it owns, which costs tens of milliseconds per widget, so it
  // stays parented there and only its visibility follows the reveal.
  function applyHidden() {
    if (!ownSlot) return
    // Snapshot the teardown destinations while the scene is still reachable.
    managedSectionRow = sectionRow
    managedLayoutOrder = layoutOrder()
    var next = hiddenSlots()
    var moved = []
    var returned = false
    for (var i = 0; i < managedSlots.length; i++) {
      var gone = managedSlots[i]
      if (gone && next.indexOf(gone) === -1 && returnSlot(gone)) {
        moved.push(gone)
        returned = true
      }
    }
    var inStrip = root.rowMode
    for (var j = 0; j < next.length; j++) {
      // An always-hidden widget never enters the strip and never follows a
      // reveal; it comes back only while the revealAll peek is on.
      if (isAlwaysHidden(next[j]) && !root.revealAll) {
        if (returnSlot(next[j])) {
          moved.push(next[j])
          returned = true
        }
        show(next[j], false)
        continue
      }
      if (inStrip) {
        if (next[j].parent !== stripFlow) {
          next[j].parent = stripFlow
          moved.push(next[j])
        }
        // A slot switching to the strip mid-fade must not carry the cascade
        // transform into a card that does its own fade.
        resetTransform(next[j])
        // Parked in the strip either way, so this flag is the whole reveal: a
        // collapsed strip has no visible child and the Flow closes over it.
        show(next[j], root.expanded)
      } else {
        if (returnSlot(next[j])) {
          moved.push(next[j])
          returned = true
        }
        // A collapsing widget stays mounted until its fade has finished, so
        // the section gives the width back once it is actually gone rather
        // than sliding its neighbours through it.
        show(next[j], root.expanded || (!root.rowMode && root.revealProgress > 0.001))
      }
    }
    // Re-append so the tray block is the last thing in the strip whatever
    // order the slots arrived in. Only when a slot actually moved: parking it
    // on a null parent takes it out of every window, which loses its scene
    // graph exactly like a slot changing window, so it needs the same repaint
    // nudge and there is no reason to pay for that on an idempotent pass.
    if (inStrip && moved.length > 0) {
      stripTrayRow.parent = null
      stripTrayRow.parent = stripFlow
      moved.push(stripTrayRow)
    }
    // Once per pass: reordering re-parents every slot the Row holds.
    if (returned) restoreOrder()
    managedSlots = next
    if (moved.length > 0) repaintMoved(moved)
    // A rebuild mid-animation has to land on the current frame of the cascade.
    applyReveal()
  }

  // Pocket-style cascade, inline mode only: each revealable slot fades and
  // grows out of the indicator, the one nearest it leading. Row mode keeps the
  // card's own fade.
  function applyReveal() {
    if (root.rowMode) return
    var list = root.revealableSlots
    var n = list.length
    for (var i = 0; i < n; i++) {
      var slot = list[i]
      if (!slot) continue
      // Layout order puts the slot nearest the chevron last, and that one
      // leads, so the index is counted from the far end.
      var f = Model.revealFraction(root.revealProgress, n - 1 - i, n)
      slot.transformOrigin = root.vertical ? Item.Bottom : Item.Right
      slot.opacity = f
      slot.scale = 0.6 + 0.4 * f
    }
    // Faded out: hand the width back and drop the transform.
    if (!root.expanded && root.revealProgress <= 0.001) {
      for (var j = 0; j < n; j++) {
        if (!list[j]) continue
        resetTransform(list[j])
        show(list[j], false)
      }
    }
  }

  // Never leave a host-owned slot carrying our cascade transform: a slot that
  // left the hidden set, moved to the strip or outlived this widget is drawn
  // by the bar, not by us.
  function resetTransform(slot) {
    slot.opacity = 1
    slot.scale = 1
    slot.transformOrigin = Item.Center
  }

  // A positioner only drives one axis: the section Row sets x and never
  // touches y. The strip is a Flow and it wraps, so a slot handed back from
  // its second or third line keeps that line's y and draws below the bar:
  // invisible, unclickable, and with x, width and visible all still reading
  // correct. Only on the way back, never while parked: a Flow does not
  // relayout on a position-only change, so zeroing y under a slot it has
  // already wrapped would collapse the strip's rows onto the first line.
  function clearCrossAxis(slot) {
    slot.y = 0
  }

  // A slot waiting for its repaint stays hidden until repaintTimer shows it,
  // so the re-apply that a re-parent triggers cannot cancel the nudge by
  // setting `visible` back to true within the same frame.
  function show(slot, visible) {
    if (repaintQueue.indexOf(slot) === -1) slot.visible = visible
  }

  // A slot that changed window keeps the scene graph nodes it built for the
  // old one, so it lands in the strip (or back in the bar) correctly sized,
  // hovering and clicking fine, and completely unpainted. Hiding it now and
  // showing it a frame later rebuilds those nodes against the window it
  // actually lives in. Nothing else marks a moved item dirty.
  function repaintMoved(moved) {
    var queue = repaintQueue.slice()
    for (var i = 0; i < moved.length; i++) {
      moved[i].visible = false
      if (queue.indexOf(moved[i]) === -1) queue.push(moved[i])
    }
    repaintQueue = queue
    repaintTimer.restart()
  }

  // Back under the section Row. Re-parenting appends, so the caller fixes the
  // Row's child order once the whole pass is done. Reports whether it moved.
  function returnSlot(slot) {
    // Never orphan a host-owned slot when the row is unavailable.
    var row = sectionRow || managedSectionRow
    if (!row) {
      resetTransform(slot)
      show(slot, true)
      return false
    }
    var moved = slot.parent !== row
    if (moved) {
      slot.parent = row
      clearCrossAxis(slot)
    }
    resetTransform(slot)
    show(slot, true)
    return moved
  }

  // The section Row lays its children out in child order, and re-parenting
  // only ever appends, so a slot back from the strip would draw at the end of
  // the section. QQuickItem::stackAfter is not exposed to QML here, so the
  // order is rebuilt by detaching every slot the Row holds and re-appending
  // them in layout order. The slots are parked on the bar window's own
  // content item, never another window, so nothing loses its scene graph and
  // no repaint nudge is needed. The Row reference is taken first: detaching
  // this widget's own slot invalidates the sectionRow binding mid-shuffle.
  // Synchronous, so no frame is drawn while the Row is empty.
  function restoreOrder(rowOverride, orderOverride) {
    var row = rowOverride || sectionRow
    if (!row) return
    // If the window is unavailable during teardown, row.parent is a
    // same-window parking item, so no slot loses its scene graph.
    var host = (root.QsWindow.window ? root.QsWindow.window.contentItem : null) || row.parent
    if (!host) return
    var placed = []
    collectSlots(row.children, placed)
    // A supplied snapshot wins even when empty: ownSlot is dead by teardown.
    var order = orderOverride === undefined || orderOverride === null ? layoutOrder() : orderOverride
    placed.sort(function(a, b) { return rank(a, order) - rank(b, order) })
    for (var i = 0; i < placed.length; i++) placed[i].parent = host
    for (var j = 0; j < placed.length; j++) placed[j].parent = row
  }

  // Runs from Component.onDestruction, so the repaint queue is dropped first
  // and every slot is shown outright rather than through show(): a disable or
  // reload landing inside repaintTimer's frame would otherwise strand slots
  // hidden, with no timer left alive to show them again. They may draw stale
  // for a frame; the layout write that removes this widget rebuilds them.
  function releaseHidden() {
    repaintQueue = []
    // Snapshot wins: the sectionRow binding reads through the dead ownSlot.
    var row = managedSectionRow || sectionRow
    var returned = false
    // Never orphan a host-owned slot: a null parent drops another plugin's
    // widget out of the scene until the next structural layout write.
    for (var i = 0; i < managedSlots.length; i++) {
      var slot = managedSlots[i]
      if (!slot) continue
      if (row && slot.parent !== row) {
        slot.parent = row
        clearCrossAxis(slot)
        returned = true
      }
      resetTransform(slot)
      slot.visible = true
    }
    if (returned) restoreOrder(row, managedLayoutOrder)
    managedSlots = []
    managedSectionRow = null
    managedLayoutOrder = []
  }

  // The host slot carries the registry's display name for a registered widget;
  // a `type: command` or `qml` entry has no metadata, so the id-derived label
  // is the fallback. `placed` is where the layout has it; `hidden` is what the
  // popup shows.
  function widgetName(slot) {
    var meta = slot.registryMetadata
    var name = meta && meta.displayName ? String(meta.displayName).trim() : ""
    return name || Model.displayLabel(slot.moduleName)
  }

  function widgetRow(slot, placed) {
    var id = slot.moduleName
    return {
      id: id,
      name: widgetName(slot),
      placed: placed,
      staged: stagedWidgets[id] !== undefined,
      hidden: stagedHidden(id, placed),
      always: root.alwaysHiddenIds.indexOf(id) !== -1
    }
  }

  function stagedHidden(id, placed) {
    var staged = stagedWidgets[id]
    return staged === undefined ? placed : staged === true
  }

  // Settings-only write, like togglePin: the host patches the entry in place,
  // so the popup survives the click and no slot is re-parented. Ids without a
  // slot stay in the list, because a disabled plugin may come back.
  function toggleAlwaysHidden(id) {
    var present = root.alwaysHiddenIds.indexOf(id) === -1
    persistSettings({ alwaysHidden: Model.setMembership(root.alwaysHiddenIds, id, present) })
  }

  // Staging a widget back to what the layout already says drops the override,
  // so toggling a row twice commits nothing.
  function stageWidget(id, hidden, placed) {
    var next = {}
    for (var key in stagedWidgets) next[key] = stagedWidgets[key]
    if (hidden === placed) delete next[id]
    else next[id] = hidden
    stagedWidgets = next
  }

  // One shell command: each `omarchy bar move` is its own shell.json write and
  // two racing writes would lose one. Newly hidden widgets land in front of
  // the chevron in row order, revealed ones behind it back-to-front, so a
  // batch keeps its relative order either way. The overrides are deliberately
  // left standing — the write rebuilds this widget, which is what clears
  // them, and dropping them first would flash every hidden widget back in.
  function commitStagedWidgets() {
    var rows = sectionWidgets
    var mine = ownSlot
    var hide = [], show = []
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].staged) continue
      if (rows[i].hidden) hide.push(rows[i].id)
      else show.push(rows[i].id)
    }
    if (!mine || (hide.length === 0 && show.length === 0)) {
      stagedWidgets = ({})
      return
    }
    var parts = []
    for (var h = 0; h < hide.length; h++) parts.push(moveCommand(hide[h], mine.region, "--before"))
    for (var s = show.length - 1; s >= 0; s--) parts.push(moveCommand(show[s], mine.region, "--after"))
    root.bar.run(parts.join(" && "))
  }

  function moveCommand(id, region, relation) {
    return "omarchy bar move " + Util.shellQuote(id)
      + " --section " + Util.shellQuote(region)
      + " " + relation + " " + Util.shellQuote(root.moduleName)
  }

  // The divider is the whole point of the widget: it stays even with no icons.
  visible: true
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  onOwnSlotChanged: reapplySoon()
  onExpandedChanged: applyHidden()
  onRowModeChanged: applyHidden()
  onStagedWidgetsChanged: applyHidden()
  onAlwaysHiddenIdsChanged: applyHidden()
  onRevealAllChanged: applyHidden()
  onRevealProgressChanged: applyReveal()
  // A Flickable keeps its offset, so a menu reopened after scrolling the
  // widget list would start part-way down with the Behaviour toggles out of
  // sight. Same reset the tray menu does.
  onManagePopupOpenChanged: {
    if (managePopupOpen) manageFlick.contentY = 0
    else commitStagedWidgets()
  }
  Component.onCompleted: reapplySoon()
  Component.onDestruction: releaseHidden()

  Timer {
    id: reapplyTimer
    interval: 0
    onTriggered: root.applyHidden()
  }

  // One frame after the move, so the item has been through a scene graph pass
  // in its new window. State is read now, not when the move was queued: a
  // collapse, mode switch or layout write can land inside that frame, and
  // showing a slot on the strength of stale state would leak a hidden widget
  // back into the bar. Owned by this widget, so it dies with it rather than
  // running against a corpse.
  Timer {
    id: repaintTimer
    interval: 16
    onTriggered: {
      var queue = root.repaintQueue
      root.repaintQueue = []
      for (var i = 0; i < queue.length; i++) {
        var slot = queue[i]
        // A slot the host has since rebuilt or moved elsewhere is not ours to
        // show; the next apply pass owns whatever replaced it.
        if (!slot || (slot.parent !== stripFlow && slot.parent !== root.sectionRow)) continue
        // Still in the hidden set: follow the section. Out of it: back in the
        // bar for good.
        slot.visible = root.managedSlots.indexOf(slot) === -1
          || (root.expanded && !(root.isAlwaysHidden(slot) && !root.revealAll))
      }
    }
  }

  // A structural shell.json write rebuilds every slot on every monitor (this
  // widget with them); the section Row also reports a child list change, which
  // covers a slot appearing or leaving without a rebuild. The deferred pass
  // coalesces the burst.
  Connections {
    target: root.sectionRow

    function onChildrenChanged() {
      if (!root) return
      root.slotRevision++
      root.reapplySoon()
    }
  }

  // Slots moving in and out of the strip change what sectionSlots() finds, so
  // the manage list has to recompute off this too.
  Connections {
    target: stripFlow

    function onChildrenChanged() {
      if (!root) return
      root.slotRevision++
    }
  }

  Connections {
    target: root.bar

    function onLayoutConfigChanged() {
      if (!root) return
      root.slotRevision++
      root.reapplySoon()
    }
  }

  // The host binds ModuleSlot.activeItem one pass after it mounts the widget,
  // so the slot is legitimately out of reach for a moment on a cold start.
  // Only a slot that never turns up means the scene shape changed under us,
  // and then the widget is a plain tray drawer.
  Timer {
    interval: 3000
    running: true
    onTriggered: if (!root.ownSlot) console.warn("omaice: own bar slot not reachable; only tray icons are hidden")
  }

  // Optional timeout on top of click-to-dismiss, off unless rehideSeconds is
  // set. Counts down only while the pointer is off the section and no popup
  // of ours is up, so it never closes under someone who is reading it.
  Timer {
    id: rehideTimer
    interval: root.rehideSeconds * 1000
    running: root.expanded && root.rehideSeconds > 0 && !root.sectionHovered && !root.popupOpen
    onTriggered: root.collapse()
  }

  // Hover mode closes shortly after the pointer leaves the bar, like the
  // first-party drawer did, but without snapping shut on the revealed items.
  Timer {
    id: hoverCollapseTimer
    interval: 400
    running: root.revealOnHover && root.expanded && !root.sectionHovered && !root.popupOpen
    onTriggered: root.collapse()
  }

  IpcHandler {
    target: "io.github.terrifiedbug.omaice"

    function toggle(): void { root.toggle() }
    // Not "show": `qs ipc call <target> show` is swallowed by qs's own show
    // subcommand, so the method would be unreachable from the command line.
    function reveal(): void { root.expand() }
    function hide(): void { root.collapse() }
    // The only way to peek at the always-hidden set; any collapse clears it.
    function revealAll(): void {
      root.revealAll = true
      root.expand()
    }
    function opened(): string { return root.expanded ? "true" : "false" }
  }

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int pinnedWidth: pinnedRow.implicitWidth
      readonly property int drawerBlockWidth: expandIcon.implicitWidth + Math.round(root.revealExtent)

      implicitWidth: pinnedWidth + drawerBlockWidth
      implicitHeight: root.barSize

      Item {
        id: drawerArea
        x: 0
        width: horizontalTrayRoot.drawerBlockWidth
        height: root.barSize
        visible: true

        // Hover only ever opens. The collapse is hoverCollapseTimer, so moving
        // the pointer onto a revealed sibling does not snap the section shut.
        HoverHandler {
          onHoveredChanged: if (root.revealOnHover && hovered) root.expand()
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          x: Math.round(root.revealExtent)
          text: root.iconGlyph
          // One behaviour for every preset: a half turn on reveal. The dot and
          // dots glyphs are symmetric, so for them it reads as a static mark.
          textRotation: root.expanded ? 180 : 0
          // No tooltip: it renders below the bar, on top of the row strip the
          // click is about to open.
          onPressed: function(button) {
            if (button === Qt.LeftButton) root.toggle()
            else if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }

          Behavior on textRotation {
            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
          }
        }

        Item {
          id: trayClip
          x: 0
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(root.revealExtent)
          height: root.barSize
          clip: true

          Row {
            id: trayIcons
            x: Math.round(root.revealExtent) - root.drawerExtent
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.rowMode ? [] : root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: drawerArea.x + horizontalTrayRoot.drawerBlockWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int pinnedHeight: pinnedCol.implicitHeight
      readonly property int drawerBlockHeight: expandIcon.implicitHeight + Math.round(root.revealExtent)

      implicitWidth: root.barSize
      implicitHeight: pinnedHeight + drawerBlockHeight

      Item {
        id: drawerArea
        y: 0
        width: root.barSize
        height: verticalTrayRoot.drawerBlockHeight
        visible: true

        // Hover only ever opens; see the horizontal layout.
        HoverHandler {
          onHoveredChanged: if (root.revealOnHover && hovered) root.expand()
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          y: Math.round(root.revealExtent)
          text: root.iconGlyph
          // Same half turn as the horizontal bar, on top of the 90° the
          // vertical bar draws its glyphs at.
          textRotation: 90 + (root.expanded ? 180 : 0)
          // No tooltip: it renders below the bar, on top of the row strip the
          // click is about to open.
          onPressed: function(button) {
            if (button === Qt.LeftButton) root.toggle()
            else if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }

          Behavior on textRotation {
            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
          }
        }

        Item {
          id: trayClip
          y: 0
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: Math.round(root.revealExtent)
          clip: true

          Column {
            id: trayIcons
            y: Math.round(root.revealExtent) - root.drawerExtent
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: drawerArea.y + verticalTrayRoot.drawerBlockHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  // Row reveal surface. One layer-shell window per bar instance (so per
  // monitor), spanning the full width and starting at the bar's screen edge so
  // that it covers bar + strip: the host positions a widget's keyboard panel
  // at anchorWindow.height and assumes that window is flush with the edge, so
  // a widget clicked inside the strip opens its panel below the strip rather
  // than on top of it. The bar band of the window is transparent and outside
  // the input mask, so bar clicks fall through. Not a popout: widgets in here
  // open their own.
  PanelWindow {
    id: stripWindow

    readonly property bool atBottom: root.bar && root.bar.position === "bottom"
    // The card is the content plus its border on each side.
    readonly property int borderWidth: 1
    readonly property int rowsHeight: Math.round(stripFlow.childrenRect.height)
    // Collapsed, the card measures nothing whatever the Flow still reports:
    // the slots stay parented in here, so the geometry has to follow the
    // reveal rather than the content. A zero card leaves a bar-height surface
    // with an empty input mask, which is the same nothing an unmapped one was.
    readonly property int cardHeight: root.expanded && rowsHeight > 0 ? rowsHeight + borderWidth * 2 : 0
    readonly property int contentWidth: Math.round(stripFlow.childrenRect.width)
    readonly property int cardWidth: root.expanded && contentWidth > 0 ? contentWidth + borderWidth * 2 : 0
    // An anchored layer surface spans the screen, but the window's own `width`
    // still reports its implicit size (500), so geometry inside is measured
    // off the screen instead.
    readonly property int surfaceWidth: screen ? screen.width : 0
    // Left edge of the chevron in screen coordinates, so the strip hangs off
    // the divider rather than the section's right margin. The bar surface is
    // flush with its screen edge and full width, so its content x is screen x.
    // mapToItem is a one-shot, hence the TransformWatcher dependency; the
    // reveal is a dependency too, so every open re-measures. -1 means the
    // chevron is not placeable yet (mid-rebuild), and the strip falls back to
    // the section's right margin rather than drawing at the screen's left.
    readonly property int chevronX: {
      slotWatcher.transform  // reactive dependency
      root.expanded          // re-measure on every reveal
      var host = root.QsWindow.window ? root.QsWindow.window.contentItem : null
      if (!root.ownSlot || !host || root.ownSlot.width <= 0) return -1
      var x = Math.round(root.ownSlot.mapToItem(host, 0, 0).x)
      return x > 0 ? x : -1
    }
    readonly property int leftEdge: chevronX < 0 ? Style.space(8) : chevronX
    readonly property int maxWidth: Math.max(0, surfaceWidth - leftEdge - Style.space(8))

    // Tracks every layout change between the bar's content surface and the
    // chevron's slot, which is what keeps chevronX live as widgets come and go.
    TransformWatcher {
      id: slotWatcher
      a: root.QsWindow.window ? root.QsWindow.window.contentItem : null
      b: root.ownSlot
    }

    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    // Mapped for as long as row mode is on, not only while the section is
    // open: the hidden widgets live in here, and unmapping would mean handing
    // every one of them back to the bar on each collapse and taking them again
    // on each reveal. Collapsed, this is a transparent, bar-height,
    // click-through surface that draws nothing.
    visible: root.rowMode
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: !atBottom; bottom: atBottom; left: true; right: true }
    // Both declared, not just height: a widget parked in the strip anchors
    // its own popup to this window, and PopupCard clamps the popup's x against
    // anchorWindow.width. Left at its implicit default the window reports
    // 500px and every popup opened from the strip gets shoved to the left.
    implicitWidth: surfaceWidth
    implicitHeight: root.barSize + cardHeight
    // Declared as well as implicit: the strip maps while the repaint nudge
    // still holds its content invisible, and a surface committed at bar
    // height keeps that height, leaving the card outside it on reveal. The
    // window's own `height` follows the card as it opens.
    height: root.barSize + cardHeight
    WlrLayershell.namespace: "omaice-strip"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Input only over the drawn strip; the bar band and the empty width of the
    // surface pass clicks through to whatever is under them.
    mask: Region {
      x: stripCard.x
      y: stripCard.y
      width: stripCard.width
      height: stripCard.height
    }

    Rectangle {
      id: stripCard
      // Starts under the chevron (or at the right margin when the chevron is
      // not placeable) and grows right; the clamp only matters if a single
      // unwrappable widget is wider than the space beside it.
      x: stripWindow.chevronX < 0
        ? Math.max(0, stripWindow.surfaceWidth - Style.space(8) - width)
        : Math.max(0, Math.min(stripWindow.chevronX, stripWindow.surfaceWidth - Style.space(8) - width))
      y: stripWindow.atBottom ? 0 : root.barSize
      width: stripWindow.cardWidth
      height: stripWindow.cardHeight
      radius: Style.cornerRadius
      // The strip is a popup surface hanging below the bar, so its fill
      // follows the popup theme and ignores bar transparency.
      border.width: stripWindow.borderWidth
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
      color: Color.popups.background
      opacity: root.expanded ? 1 : 0
      // The parked slots are already hidden, but the tray block is not: its
      // Repeater is keyed on row mode, not the reveal, and a zero-size card
      // does not clip, so without this it would paint outside the card.
      visible: root.expanded

      // Fade in on open. The card goes the instant the section collapses, so
      // the way out is instant whatever this says.
      Behavior on opacity {
        NumberAnimation { duration: 140 }
      }

      HoverHandler { id: stripHover }

      // Left to right, wrapping at the screen width; the hidden slots are
      // re-parented in here by applyHidden(), the tray block re-appended last.
      Flow {
        id: stripFlow
        x: stripWindow.borderWidth
        y: stripWindow.borderWidth
        width: stripWindow.maxWidth
        spacing: 0
        layoutDirection: Qt.LeftToRight

        Row {
          id: stripTrayRow
          spacing: root.trayItemGap

          Repeater {
            model: root.rowMode ? root.drawerItems : []
            TrayItem {}
          }
        }
      }
    }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(300))
    // No fixed cap: the card grows with the two lists up to the viewport
    // (PopupCard.availableCardHeight = screen minus bar and margins), then
    // scrolls. The tray/app lists can be long; 420px forced scrolling on
    // bars with only a handful of managed items.
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

    // Past the viewport the card scrolls rather than running off the
    // screen. Same pattern as the tray menu's rows; the Behaviour toggles
    // sit above the lists so they never need it.
    Flickable {
      id: manageFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: manageColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: manageColumn
        width: manageFlick.width
        spacing: Style.space(8)

        Text {
          text: "Hidden section"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        PanelSeparator {
          width: manageColumn.width
          foreground: root.foreground
        }

        Text {
          text: "Behaviour"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        // The kit Toggle parks its switch in a 54px bordered box, which dwarfs
        // the icon dropdown and the lists below it. These rows use the bare
        // ToggleSwitch on a plain row, the same shape the tray and widget lists
        // already have, and ask the switch for a smaller track instead of
        // scaling a big one down.
        Item {
          id: rowModeRow
          width: manageColumn.width
          implicitHeight: Style.spacing.controlHeight
          activeFocusOnTab: true

          function flip() { root.persistSettings({ revealMode: root.revealMode === "row" ? "inline" : "row" }) }

          Keys.onReturnPressed: rowModeRow.flip()
          Keys.onEnterPressed: rowModeRow.flip()
          Keys.onSpacePressed: rowModeRow.flip()

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: rowModeSwitch.left
            anchors.rightMargin: Style.space(8)
            text: "Show in a row below the bar"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          // Deliberately smaller than the kit's 22px track: the row is the
          // height of a control, not of a card. The row owns the click, so the
          // switch is presentation only, but the ring is switched back on by
          // hand: it follows `interactive` and is what shows hover and focus.
          ToggleSwitch {
            id: rowModeSwitch
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            trackHeight: Style.space(16)
            interactive: false
            cursorRing: true
            cursorPad: Style.space(4)
            hasCursor: rowModeRow.activeFocus || rowModeMouse.containsMouse
            checked: root.revealMode === "row"
            foreground: root.foreground
          }

          // The whole row is the click target, as the kit Toggle's is.
          MouseArea {
            id: rowModeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rowModeRow.flip()
          }
        }

        // The only warning worth the space: a vertical bar has no row to open.
        Text {
          textFormat: Text.PlainText
          visible: root.vertical
          width: manageColumn.width
          text: "Needs a horizontal bar"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Item {
          id: hoverRow
          width: manageColumn.width
          implicitHeight: Style.spacing.controlHeight
          activeFocusOnTab: true

          function flip() { root.persistSettings({ revealOnHover: !root.revealOnHover }) }

          Keys.onReturnPressed: hoverRow.flip()
          Keys.onEnterPressed: hoverRow.flip()
          Keys.onSpacePressed: hoverRow.flip()

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: hoverSwitch.left
            anchors.rightMargin: Style.space(8)
            text: "Reveal on hover"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          ToggleSwitch {
            id: hoverSwitch
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            trackHeight: Style.space(16)
            interactive: false
            cursorRing: true
            cursorPad: Style.space(4)
            hasCursor: hoverRow.activeFocus || hoverMouse.containsMouse
            checked: root.revealOnHover
            foreground: root.foreground
          }

          MouseArea {
            id: hoverMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hoverRow.flip()
          }
        }

        // The kit Dropdown assigns `value` itself on select, which overwrites
        // the declarative binding, so the Binding below re-asserts the setting
        // and keeps a CLI edit in sync while the popup is open.
        Dropdown {
          id: iconPicker
          width: manageColumn.width
          label: "Indicator icon"
          foreground: root.foreground
          fontFamily: root.fontFamily
          value: root.icon
          options: [
            { value: "chevron", label: "Chevron" },
            { value: "dot", label: "Dot" },
            { value: "dots", label: "Three dots" }
          ]
          onChanged: function(value) { root.persistSettings({ icon: value }) }
        }

        Binding {
          target: iconPicker
          property: "value"
          value: root.icon
        }

        PanelSeparator {
          width: manageColumn.width
          foreground: root.foreground
        }

        Text {
          visible: root.allItems.length === 0
          text: "No tray items reporting."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Text {
          text: "Tray icons"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.allItems
          delegate: Item {
            id: rowRoot
            required property var modelData
            required property int index
            width: manageColumn.width
            implicitHeight: 28

            readonly property string itemId: String(modelData.id || "")
            readonly property string displayName: {
              // Title first: the app's own label when it sets one. Some apps
              // (Slack) leave Title empty and put transient state ("You have
              // unread messages") in the tooltip, so try the desktop-entry
              // name — resolved from the SNI id, Electron ids end
              // "_status_icon_N" — BEFORE falling back to the tooltip.
              var t = String(modelData.title || "").trim()
              if (t) return t
              var id = String(modelData.id || "")
              var appKey = id.replace(/_status_icon_\d+$/, "")
              if (appKey && typeof DesktopEntries.heuristicLookup === "function") {
                var entry = DesktopEntries.heuristicLookup(appKey)
                if (entry) {
                  var entryName = String(entry.name || "").trim()
                  if (entryName) return entryName
                }
              }
              var tt = String(modelData.tooltipTitle || "").trim()
              if (tt) return tt
              var slash = id.lastIndexOf("/")
              return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
            }
            readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
            readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1

            // Same shape as a "Bar widgets" row: name on the left, dimmed
            // while hidden, actions on the right. No icon, so the two lists
            // read as one.
            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: rowHideBtn.left
              anchors.rightMargin: Style.space(8)
              text: rowRoot.displayName
              color: rowRoot.isHidden ? Qt.darker(root.foreground, 1.4) : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: rowPinBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              iconText: "\uf08d"
              text: rowRoot.isPinned ? "Unpin" : "Pin"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: Style.font.bodySmall
              fontSize: Style.font.bodySmall
              onClicked: root.togglePin(rowRoot.itemId)
            }

            Button {
              id: rowHideBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: rowPinBtn.left
              anchors.rightMargin: Style.space(6)
              iconText: "\uf06e"
              text: rowRoot.isHidden ? "Show" : "Hide"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: Style.font.bodySmall
              fontSize: Style.font.bodySmall
              onClicked: root.toggleHide(rowRoot.itemId)
            }
          }
        }

        PanelSeparator {
          width: manageColumn.width
          foreground: root.foreground
        }

        Text {
          text: "Bar widgets"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        // Hiding a widget is a move relative to the chevron, not a flag: the
        // divider's meaning is positional, so the layout has to say it too.
        Repeater {
          model: root.sectionWidgets
          delegate: Item {
            id: widgetRow
            required property var modelData
            width: manageColumn.width
            implicitHeight: 28

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: widgetAlwaysBtn.left
              anchors.rightMargin: Style.space(8)
              text: widgetRow.modelData.name
              color: (widgetRow.modelData.hidden || widgetRow.modelData.always)
                ? Qt.darker(root.foreground, 1.4)
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: widgetToggleBtn
              // An always-hidden widget ignores its side of the chevron, so
              // the positional control would be a lie for that row.
              visible: !widgetRow.modelData.always
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              iconText: "\uf06e"  // nf-fa-eye
              text: widgetRow.modelData.hidden ? "Show" : "Hide"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: Style.font.bodySmall
              fontSize: Style.font.bodySmall
              onClicked: root.stageWidget(widgetRow.modelData.id, !widgetRow.modelData.hidden, widgetRow.modelData.placed)
            }

            Button {
              id: widgetAlwaysBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: widgetToggleBtn.visible ? widgetToggleBtn.left : parent.right
              anchors.rightMargin: widgetToggleBtn.visible ? Style.space(6) : 0
              iconText: "\uf070"  // nf-fa-eye_slash
              text: widgetRow.modelData.always ? "Stop hiding" : "Always hide"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: Style.font.bodySmall
              fontSize: Style.font.bodySmall
              onClicked: root.toggleAlwaysHidden(widgetRow.modelData.id)
            }
          }
        }

      }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // The card fades out over 140ms (visible stays true for that whole time --
    // see PopupCard's own visible: open || card.opacity > 0), so resetting on
    // "open" would swap a live submenu for the root menu mid-fade: a visible
    // flash, and a resize/reposition if the two have different geometry. Wait
    // for the fade to actually finish. Switching to a different tray item
    // still resets immediately, from openTrayMenu() itself.
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    padding: Style.space(8)
    borderColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    // Column skips invisible children but keeps reporting their height, so
    // read the header's extent through its own visibility.
    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      // Header for a drilled-into submenu: names where we are and walks back
      // out. Pinned above the Flickable rather than scrolling with the rows,
      // so the way back stays reachable in a submenu taller than the card.
      // Only present below the root level, so the root menu is unchanged.
      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        spacing: 0

        Item {
          id: menuBackRow
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "\u2039"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            text: root.currentTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuLevelSettling) return
              // Reset before the model swap so the parent level shows from
              // the top (same ordering as the row delegate below).
              trayMenuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(11)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Color.popups.border
            opacity: 0.45
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - trayMenuPopup.menuHeaderHeight
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width
          spacing: 0

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              // Both only ever describe the root menu; inside a submenu the first
              // rows are real entries and must not be swallowed.
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              visible: !hiddenRow
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.popups.border
                opacity: 0.45
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Math.max(2, Style.cornerRadius)
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                id: menuIcon
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels: IconImage uses the logical size,
                // which leaves PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.space(8)
                text: menuRow.rowText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                text: "\u203a"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (menuRow.modelData.hasChildren) {
                    // Reset scroll BEFORE swapping the model: the swap destroys
                    // this delegate synchronously and ids stop resolving after.
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size,
      // which leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    TrayIcon {
      anchors.centerIn: parent
      width: Style.space(12)
      height: Style.space(12)
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
