const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const ids = ["a", "b", "c", "d"]

test("partitionEntries with the divider first hides nothing", () => {
  assert.deepEqual(Model.partitionEntries(ids, 0), { hidden: [], visible: ["b", "c", "d"] })
})

test("partitionEntries with the divider last hides everything before it", () => {
  assert.deepEqual(Model.partitionEntries(ids, 3), { hidden: ["a", "b", "c"], visible: [] })
})

test("partitionEntries splits around a divider in the middle", () => {
  assert.deepEqual(Model.partitionEntries(ids, 2), { hidden: ["a", "b"], visible: ["d"] })
})

test("partitionEntries with no divider keeps every entry visible", () => {
  assert.deepEqual(Model.partitionEntries(ids, -1), { hidden: [], visible: ids })
})

test("toggleBucket pinning an id drops it from hidden", () => {
  assert.deepEqual(Model.toggleBucket([], ["x"], "x", "pinned"), { pinned: ["x"], hidden: [] })
})

test("toggleBucket hiding an id drops it from pinned", () => {
  assert.deepEqual(Model.toggleBucket(["x"], [], "x", "hidden"), { pinned: [], hidden: ["x"] })
})

test("toggleBucket twice returns the id to the drawer", () => {
  const once = Model.toggleBucket([], [], "x", "pinned")
  assert.deepEqual(once, { pinned: ["x"], hidden: [] })
  assert.deepEqual(Model.toggleBucket(once.pinned, once.hidden, "x", "pinned"), { pinned: [], hidden: [] })
})

test("toggleBucket leaves other ids in place", () => {
  assert.deepEqual(Model.toggleBucket(["a"], ["b"], "c", "pinned"), { pinned: ["a", "c"], hidden: ["b"] })
})

test("normalizeRehideSeconds falls back on junk", () => {
  assert.equal(Model.normalizeRehideSeconds("abc", 10), 10)
})

test("normalizeRehideSeconds clamps to the 0..600 range", () => {
  assert.equal(Model.normalizeRehideSeconds(-5, 10), 0)
  assert.equal(Model.normalizeRehideSeconds(9999, 10), 600)
})

test("normalizeRehideSeconds rounds a numeric string", () => {
  assert.equal(Model.normalizeRehideSeconds("7.6", 10), 8)
})

test("displayLabel names a first-party id by its last segment", () => {
  assert.equal(Model.displayLabel("omarchy.keyboard-layout"), "Keyboard layout")
})

test("displayLabel names a reverse-domain plugin id", () => {
  assert.equal(Model.displayLabel("io.github.grichard99.omaproton-vpn"), "Omaproton vpn")
})

test("displayLabel passes an empty id through", () => {
  assert.equal(Model.displayLabel(""), "")
})
