// Pure helpers for the Ice divider. Qt-free so node can test them
// (test/model.test.js); the QML owns everything that touches the bar.

var MAX_REHIDE_SECONDS = 600

// Seconds before an expanded section closes on its own; 0 disables.
function normalizeRehideSeconds(value, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(0, Math.min(MAX_REHIDE_SECONDS, n))
}

// "row" reveals the hidden section in a strip under the bar; anything else is inline.
function normalizeRevealMode(value) {
  return String(value || "").trim().toLowerCase() === "row" ? "row" : "inline"
}

// Indicator presets. The chevron is the only one that reads as a direction;
// dot and dots are the quiet options, so the flip on reveal is a no-op look.
var ICONS = ["chevron", "dot", "dots"]

function normalizeIcon(value) {
  var name = String(value || "").trim().toLowerCase()
  return ICONS.indexOf(name) !== -1 ? name : "chevron"
}

// Split a section's entry ids around the divider's index: ids before it are
// the hidden region, ids after it stay visible. Divider index < 0 hides nothing.
function partitionEntries(entryIds, dividerIndex) {
  if (dividerIndex < 0 || dividerIndex >= entryIds.length) return { hidden: [], visible: entryIds.slice() }
  return { hidden: entryIds.slice(0, dividerIndex), visible: entryIds.slice(dividerIndex + 1) }
}

// Tray icon buckets are mutually exclusive: pinning un-hides, hiding unpins,
// and toggling an id already in the bucket returns it to the drawer.
function toggleBucket(pinned, hidden, id, bucket) {
  var p = pinned.filter(function(x) { return x !== id })
  var h = hidden.filter(function(x) { return x !== id })
  if (bucket === "pinned" && pinned.indexOf(id) === -1) p.push(id)
  if (bucket === "hidden" && hidden.indexOf(id) === -1) h.push(id)
  return { pinned: p, hidden: h }
}

// Human label for a layout id when no registry is reachable: the last dotted
// segment, separators as spaces, first letter upper-cased.
function displayLabel(id) {
  var text = String(id || "")
  var segment = text.substring(text.lastIndexOf(".") + 1).replace(/[-_]+/g, " ").trim()
  if (!segment) return text
  return segment.charAt(0).toUpperCase() + segment.slice(1)
}

// Id lists come from shell.json, which a hand edit can fill with anything:
// convert every entry that is there, drop blanks, nulls and duplicates, and
// treat a non-array as empty. A layout id is a string, so 0 or false is
// nonsense either way, but converting it keeps the list honest about what the
// file said rather than quietly losing an entry.
function normalizeIdList(value) {
  if (!(value instanceof Array)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    if (value[i] === null || value[i] === undefined) continue
    var id = String(value[i])
    if (id && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

// Set add/remove that never mutates: the caller hands the result straight to
// persistSettings, and a mutated settings array would not report a change.
function setMembership(ids, id, present) {
  var out = normalizeIdList(ids)
  if (!present) return out.filter(function(x) { return x !== id })
  if (out.indexOf(id) === -1) out.push(id)
  return out
}

// Per-item progress for the cascade: item `index` waits `stagger * index` of
// the run before it starts, then covers the rest. The stagger shrinks as the
// count grows so the last item always finishes with the animation.
function revealFraction(progress, index, count) {
  var p = Number(progress)
  if (!isFinite(p)) p = 0
  p = Math.max(0, Math.min(1, p))
  var n = Math.max(1, Math.floor(Number(count) || 0))
  var i = Math.max(0, Math.min(n - 1, Math.floor(Number(index) || 0)))
  var stagger = n > 1 ? Math.min(0.15, 0.6 / (n - 1)) : 0
  var span = 1 - stagger * (n - 1)
  return Math.max(0, Math.min(1, (p - stagger * i) / span))
}

if (typeof module !== "undefined") {
  module.exports = {
    displayLabel: displayLabel,
    normalizeIcon: normalizeIcon,
    normalizeIdList: normalizeIdList,
    normalizeRehideSeconds: normalizeRehideSeconds,
    normalizeRevealMode: normalizeRevealMode,
    partitionEntries: partitionEntries,
    revealFraction: revealFraction,
    setMembership: setMembership,
    toggleBucket: toggleBucket
  }
}
