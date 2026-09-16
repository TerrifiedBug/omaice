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

test("normalizeRevealMode accepts row case-insensitively", () => {
  assert.equal(Model.normalizeRevealMode("Row"), "row")
})

test("normalizeRevealMode falls back to inline on junk", () => {
  assert.equal(Model.normalizeRevealMode(undefined), "inline")
  assert.equal(Model.normalizeRevealMode("sideways"), "inline")
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

test("normalizeIcon accepts a preset case-insensitively", () => {
  assert.equal(Model.normalizeIcon("Dots"), "dots")
})

test("normalizeIcon falls back to the chevron on anything else", () => {
  assert.equal(Model.normalizeIcon(undefined), "chevron")
  assert.equal(Model.normalizeIcon("custom"), "chevron")
})

test("normalizeIdList turns junk into an empty list", () => {
  assert.deepEqual(Model.normalizeIdList(undefined), [])
  assert.deepEqual(Model.normalizeIdList("a,b"), [])
})

test("normalizeIdList drops blanks and duplicates", () => {
  assert.deepEqual(Model.normalizeIdList(["a", "a", ""]), ["a"])
})

test("normalizeIdList converts entries a hand edit left untyped", () => {
  assert.deepEqual(Model.normalizeIdList([0, false, null, "a"]), ["0", "false", "a"])
})

test("setMembership adding twice keeps one entry", () => {
  const once = Model.setMembership([], "a", true)
  assert.deepEqual(once, ["a"])
  assert.deepEqual(Model.setMembership(once, "a", true), ["a"])
})

test("setMembership removing an absent id copies the list", () => {
  const ids = ["a"]
  const out = Model.setMembership(ids, "b", false)
  assert.deepEqual(out, ["a"])
  assert.notEqual(out, ids)
})

test("setMembership removing drops every occurrence", () => {
  assert.deepEqual(Model.setMembership(["a", "b"], "a", false), ["b"])
})

test("revealFraction is 1 for every item at full progress", () => {
  assert.equal(Model.revealFraction(1, 0, 4), 1)
  assert.equal(Model.revealFraction(1, 3, 4), 1)
})

test("revealFraction is 0 for every item at zero progress", () => {
  assert.equal(Model.revealFraction(0, 0, 4), 0)
  assert.equal(Model.revealFraction(0, 3, 4), 0)
})

test("revealFraction staggers so the first item leads", () => {
  assert.ok(Model.revealFraction(0.15, 0, 4) > 0)
  assert.equal(Model.revealFraction(0.15, 1, 4), 0)
})

test("revealFraction passes progress through for a single item", () => {
  assert.equal(Model.revealFraction(0.42, 0, 1), 0.42)
})

test("revealFraction clamps junk progress to zero", () => {
  assert.equal(Model.revealFraction(NaN, 0, 3), 0)
  assert.equal(Model.revealFraction(5, 2, 3), 1)
})
