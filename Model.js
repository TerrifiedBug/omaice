// Pure helpers for the Ice divider. Qt-free so node can test them
// (test/model.test.js); the QML owns everything that touches the bar.

var MAX_REHIDE_SECONDS = 600

// Seconds before an expanded section closes on its own; 0 disables.
function normalizeRehideSeconds(value, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(0, Math.min(MAX_REHIDE_SECONDS, n))
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

if (typeof module !== "undefined") {
  module.exports = {
    normalizeRehideSeconds: normalizeRehideSeconds,
    partitionEntries: partitionEntries,
    toggleBucket: toggleBucket
  }
}
