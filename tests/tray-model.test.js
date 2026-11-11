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
  assert.equal(Model.replacementGlyph(steam), "\u{f1b6}")
  assert.equal(Model.replacementGlyph(remmina), "\u{eb3a}")
  assert.equal(Model.replacementGlyph({ id: "chrome_status_icon_1", title: "ChatGPT" }), "\u{ec81}")
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

test("Spotify left-click shows its window, not a menu", () => {
  const app = Model.windowApp(spotify)
  assert.ok(app)
  assert.equal(Model.windowApp({ id: "x", title: "Spotify" }), app)
  assert.equal(Model.windowApp(steam), null)
  assert.equal(Model.windowApp({ id: "spotifyd" }), null)
  assert.equal(Model.windowApp(null), null)
})

test("the app's most recently focused window wins", () => {
  const app = Model.windowApp(spotify)
  const windows = [
    { wmClass: "firefox", address: "0x1", focusOrder: 0 },
    { wmClass: "Spotify", address: "0x2", focusOrder: 4 },
    { wmClass: "Spotify", address: "0x3", focusOrder: 2 },
    { wmClass: "Spotify", address: "", focusOrder: 1 }
  ]
  assert.equal(Model.appWindow(app, windows).address, "0x3")
  // Quickshell's HyprlandToplevel.address has no 0x prefix.
  assert.equal(Model.appWindow(app, [{ wmClass: "Spotify", address: "558a4fde4210" }]).address, "0x558a4fde4210")
  assert.equal(Model.appWindow(app, [{ wmClass: "firefox", address: "0x1" }]), null)
  assert.equal(Model.appWindow(app, []), null)
  assert.equal(Model.appWindow(null, windows), null)
})

test("finds the menu entry that shows the window", () => {
  const app = Model.windowApp(spotify)
  // Spotify's real menu (busctl, read-only).
  const entries = [
    { text: "Minimize to Tray" },
    { text: "Show Spotify" },
    { isSeparator: true },
    { text: "Exit" }
  ]
  assert.equal(Model.showWindowEntry(app, entries), 1)
  assert.equal(Model.showWindowEntry(app, [{ text: "Show Spotify", enabled: false }]), -1)
  assert.equal(Model.showWindowEntry(app, [{ text: "Exit" }]), -1)
  assert.equal(Model.showWindowEntry(null, entries), -1)
})

test("the glyphs setting replaces an app's icon", () => {
  const glyphs = { Spotify: "\u{f1bc}", steam: "S", remmina: "  ", warp: 3 }
  assert.equal(Model.replacementGlyph(spotify, glyphs), "\u{f1bc}")
  assert.equal(Model.replacementGlyph({ id: "x", title: "Spotify" }, glyphs), "\u{f1bc}")
  assert.equal(Model.replacementGlyph(steam, glyphs), "S")
  // Blank or non-string entries keep the built-in glyph or the app's icon.
  assert.equal(Model.replacementGlyph(remmina, glyphs), "\u{eb3a}")
  assert.equal(Model.replacementGlyph(warp, glyphs), "")
  assert.equal(Model.replacementGlyph({ id: "spotifyd" }, glyphs), "")
  assert.equal(Model.replacementGlyph(spotify, null), "")
  assert.equal(Model.replacementGlyph(spotify, ["\u{f1bc}"]), "")
  // A custom glyph changes only the icon, not the click.
  assert.equal(Model.primaryClickOpensMenu(spotify), false)
  assert.ok(Model.windowApp(spotify))
})

test("tooltips are the app's text, bounded before the host sizes its popup", () => {
  const LINES = Model.TOOLTIP_LINES
  const CHARS = Model.TOOLTIP_LINE_CHARS
  // Ordinary tooltips pass through unchanged, markup included (the host
  // draws plain text).
  assert.equal(Model.tooltipText(spotify), "Warpaint – Love Is To Die")
  assert.equal(Model.tooltipText(steam), "Steam")
  assert.equal(Model.tooltipText({ id: "nextcloud" }), "nextcloud")
  assert.equal(Model.tooltipText({ tooltipTitle: "Nextcloud\nSynced" }), "Nextcloud\nSynced")
  assert.equal(Model.tooltipText({ tooltipTitle: "<b>x</b>" }), "<b>x</b>")
  assert.equal(Model.tooltipText(null), "")
  assert.equal(Model.tooltipText({}), "")
  const exact = Array(LINES).fill("a".repeat(CHARS)).join("\n")
  assert.equal(Model.tooltipText({ tooltipTitle: exact }), exact)
  // A long line is cut, and the cut shows.
  assert.equal(Model.tooltipText({ tooltipTitle: "b".repeat(CHARS + 1) }), "b".repeat(CHARS) + "…")
  // Too many lines: the first ones are kept, the last kept one marked.
  const tall = Model.tooltipText({ tooltipTitle: "line\n".repeat(LINES * 4) }).split("\n")
  assert.equal(tall.length, LINES)
  assert.equal(tall[LINES - 1], "line…")
  assert.ok(tall.slice(0, -1).every(line => line === "line"))
  // \r\n and \r count as one line break each.
  assert.equal(Model.tooltipText({ tooltipTitle: "a\r\nb\rc" }), "a\nb\nc")
  // The reproduced case: 20,000 characters plus 60 lines.
  const huge = Model.tooltipText({ tooltipTitle: "A".repeat(20000) + "\nline".repeat(60) })
  assert.equal(huge, "A".repeat(CHARS) + "…")
  // A cut never splits a surrogate pair.
  const emoji = Model.tooltipText({ tooltipTitle: "x".repeat(CHARS - 1) + "\u{1f600}" })
  assert.equal(emoji, "x".repeat(CHARS - 1) + "…")
  // A multi-megabyte title is cut from its start, not scanned whole.
  const big = Model.tooltipText({ tooltipTitle: "z\n".repeat(4 * 1024 * 1024) })
  assert.equal(big.split("\n").length, LINES)
})

test("menu labels stay on one line", () => {
  assert.equal(Model.menuLabel("Quit"), "Quit")
  assert.equal(Model.menuLabel("Offline mode\nsecond line\r\nthird"), "Offline mode second line third")
  assert.equal(Model.menuLabel("a \n\n b\u2028c\u2029d\re"), "a b c d e")
  assert.equal(Model.menuLabel("  _Open  "), "  _Open  ")
  assert.equal(Model.menuLabel(undefined), "")
  assert.equal(Model.menuLabel(null), "")
  assert.equal(Model.menuLabel(3), "3")
})

console.log("RESULT: " + passed + " tray model tests passed")
