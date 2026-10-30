#!/usr/bin/env node
// Unit tests for TrayModel.js: app matching (id, then title, never tooltip),
// WARP icon handling, hidden menu rows, cursor stops and Tab between menus.
"use strict"
const assert = require("node:assert/strict")
const path = require("node:path")
const Model = require(path.join(__dirname, "..", "TrayModel.js"))

let passed = 0
function test(name, body) {
  body()
  passed++
  console.log("PASS: " + name)
}

// Ids and titles seen on a real session (busctl, read-only).
const warp = { id: "8F2qtUGjGB", title: "warp-taskbar", icon: "/usr/lib/warp/data/flutter_assets/assets/tray_icons/pngs/attention.png" }
const steam = { id: "steam", title: "Steam", icon: "steam_tray_mono" }
const remmina = { id: "remmina-icon", title: "Remmina", icon: "org.remmina.Remmina-status" }
const spotify = { id: "spotify-client", title: "spotify", tooltipTitle: "Warpaint – Love Is To Die" }

test("matches by status-notifier id", () => {
  assert.equal(Model.appKind(steam), "steam")
  assert.equal(Model.appKind(remmina), "remmina")
  assert.equal(Model.appKind({ id: "cloudflare-warp" }), "warp")
})

test("falls back to the title when the id is random or generic", () => {
  assert.equal(Model.appKind(warp), "warp")
  assert.equal(Model.appKind({ id: "chrome_status_icon_1", title: "ChatGPT" }), "chatgpt")
  assert.equal(Model.appKind({ id: "x", title: "Cloudflare WARP" }), "warp")
})

test("never matches on the tooltip", () => {
  assert.equal(Model.appKind(spotify), "")
  assert.equal(Model.appKind({ id: "qbittorrent", title: "qBittorrent", tooltipTitle: "Steam deck image" }), "")
  assert.equal(Model.monochrome(spotify), false)
  assert.equal(Model.replacementGlyph(spotify), "")
  assert.equal(Model.primaryClickOpensMenu(spotify), false)
})

test("needs a whole word, not a substring", () => {
  assert.equal(Model.appKind({ id: "warpinator", title: "Warpinator" }), "")
  assert.equal(Model.appKind({ id: "steamboat" }), "")
  assert.equal(Model.appKind({ id: "upstream-sync", title: "Upstream sync" }), "")
  assert.equal(Model.appKind({ id: "my-steam" }), "")
  assert.equal(Model.appKind(null), "")
  assert.equal(Model.appKind({}), "")
})

test("special cases keep their glyphs and click behaviour", () => {
  assert.equal(Model.replacementGlyph(steam), "")
  assert.equal(Model.replacementGlyph(remmina), "")
  assert.equal(Model.replacementGlyph({ id: "chrome_status_icon_1", title: "ChatGPT" }), "")
  assert.equal(Model.replacementGlyph(warp), "")
  assert.equal(Model.primaryClickOpensMenu(warp), true)
  assert.equal(Model.primaryClickOpensMenu(steam), true)
  assert.equal(Model.primaryClickOpensMenu({ id: "nm-applet", onlyMenu: true }), true)
  assert.equal(Model.primaryClickOpensMenu({ id: "nm-applet", onlyMenu: false }), false)
  assert.equal(Model.monochrome(warp), true)
  assert.equal(Model.monochrome(steam), false)
})

test("WARP attention icons drop the baked-in badge", () => {
  assert.equal(Model.warpConnectionIcon(warp), "/usr/lib/warp/data/flutter_assets/assets/tray_icons/pngs/connected.png")
  const off = Object.assign({}, warp, { icon: "image://icon/x/attention_disconnected.png?path=/y" })
  assert.equal(Model.warpConnectionIcon(off), "image://icon/x/disconnected.png?path=/y")
  const plain = Object.assign({}, warp, { icon: "/a/connected.png" })
  assert.equal(Model.warpConnectionIcon(plain), "/a/connected.png")
  // Other apps keep their icon untouched, even one named attention.png.
  assert.equal(Model.warpConnectionIcon({ id: "other", title: "warpaint", icon: "/a/attention.png" }), "/a/attention.png")
})

const rows = [
  { text: "Steam", hasChildren: true },
  { isSeparator: true },
  { text: "Store" },
  { isSeparator: true },
  { isSeparator: true },
  { text: "Offline", enabled: false },
  { text: "Exit" }
]

test("hides the title entry, leading and duplicate separators at the root", () => {
  assert.deepEqual(Model.hiddenRows(rows, true, "Steam"), [true, true, false, false, true, false, false])
})

test("inside a submenu only duplicate separators are hidden", () => {
  assert.deepEqual(Model.hiddenRows(rows, false, "Steam"), [false, false, false, false, true, false, false])
  assert.deepEqual(Model.hiddenRows(rows, true, "Other app"), [false, true, false, false, true, false, false])
})

test("the cursor stops on shown, enabled, non-separator rows", () => {
  const hidden = Model.hiddenRows(rows, true, "Steam")
  assert.deepEqual(Model.cursorStops(rows, hidden), [2, 6])
  assert.deepEqual(Model.cursorStops([], []), [])
})

test("Tab moves to the adjacent tray item that has a menu", () => {
  assert.equal(Model.adjacentMenu([true, false, true], 0, 1), 2)
  assert.equal(Model.adjacentMenu([true, false, true], 2, 1), 0)
  assert.equal(Model.adjacentMenu([true, false, true], 0, -1), 2)
  assert.equal(Model.adjacentMenu([true, true, true], 1, -1), 0)
  assert.equal(Model.adjacentMenu([true], 0, 1), -1)
  assert.equal(Model.adjacentMenu([true, false], 0, 1), -1)
  assert.equal(Model.adjacentMenu([], 0, 1), -1)
})

console.log("RESULT: " + passed + " tray model tests passed")
