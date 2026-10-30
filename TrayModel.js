// Which tray item belongs to which special-cased app. Matched by the item's
// status-notifier Id first, then its Title, never by its tooltip: tooltips
// are live text the app controls (a track title, a sync status), so
// "Warpaint – Love Is To Die" must not be mistaken for Cloudflare WARP.
//
// A name matches an Id or Title that equals it or starts with it followed by
// a separator ("remmina-icon", "warp-taskbar", "Cloudflare WARP"), so
// "Warpinator" or "Steamboat" stay ordinary items. Titles are the fallback
// because some toolkits export random or generic Ids: WARP (Flutter
// tray_manager) registers a random Id with the Title "warp-taskbar", and
// Chromium apps use "chrome_status_icon_1" with the app name as Title.
var APPS = {
  steam: ["steam"],
  remmina: ["remmina", "org.remmina.remmina"],
  chatgpt: ["chatgpt", "openai"],
  warp: ["warp-taskbar", "cloudflare-warp", "cloudflare"]
}

function text(value) {
  return String(value === undefined || value === null ? "" : value).trim().toLowerCase()
}

function nameMatches(value, name) {
  var subject = text(value)
  if (subject === "" || subject.indexOf(name) !== 0) return false
  if (subject.length === name.length) return true
  return /[\s\-_.:]/.test(subject.charAt(name.length))
}

function appKind(item) {
  if (!item) return ""
  var fields = [item.id, item.title]
  for (var f = 0; f < fields.length; f++) {
    for (var kind in APPS) {
      var names = APPS[kind]
      for (var n = 0; n < names.length; n++) {
        if (nameMatches(fields[f], names[n])) return kind
      }
    }
  }
  return ""
}

function itemNamed(item, kind) {
  return appKind(item) === kind
}

// Theme-aware Nerd Font glyphs for low-contrast tray bitmaps.
function replacementGlyph(item) {
  var kind = appKind(item)
  if (kind === "steam") return "\u{f1b6}"
  if (kind === "remmina") return "\u{eb3a}"
  if (kind === "chatgpt") return "\u{ec81}"
  return ""
}

// WARP advertises Activate, but its useful tray surface is the menu. Apps
// drawn with a glyph and menu-only items open their menu on left-click too.
function primaryClickOpensMenu(item) {
  return !!item && (appKind(item) !== "" || item.onlyMenu === true)
}

// WARP ships white PNGs without a symbolic icon name.
function monochrome(item) {
  return appKind(item) === "warp"
}

function warpConnectionIcon(item) {
  var icon = String(item && item.icon || "")
  if (appKind(item) !== "warp") return icon
  // WARP bakes a red badge into its attention PNGs. Render that badge separately
  // so tinting the white connection shape cannot erase the notification color.
  return icon.replace(/\/attention(_disconnected)?\.png(?=\?|$)/, function(match, disconnected) {
    return disconnected ? "/disconnected.png" : "/connected.png"
  })
}

// Menu rows the tray hides: the root entry that only repeats the app's name,
// separators leading the root menu, and the second of adjacent separators.
// `entries` is an array of { text, isSeparator, hasChildren }.
function hiddenRows(entries, atRoot, appTitle) {
  var hidden = []
  var title = text(appTitle)
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i] || {}
    var titleEntry = atRoot && i === 0 && !!entry.hasChildren && text(entry.text) === title
    var leadingSeparator = atRoot && !!entry.isSeparator && i <= 1
    var duplicateSeparator = !!entry.isSeparator && i > 0 && !!(entries[i - 1] && entries[i - 1].isSeparator)
    hidden.push(titleEntry || leadingSeparator || duplicateSeparator)
  }
  return hidden
}

// The keyboard/pointer cursor stops on rows that can be activated: shown,
// not a separator, enabled. Returns the row index for each stop.
function cursorStops(entries, hidden) {
  var stops = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i] || {}
    if (hidden[i] || entry.isSeparator || entry.enabled === false) continue
    stops.push(i)
  }
  return stops
}

// The next tray item with a menu, for Tab/Shift-Tab between app menus.
// `hasMenu` is an array of booleans, one per tray item; -1 when there is none.
function adjacentMenu(hasMenu, current, direction) {
  var count = hasMenu.length
  if (count === 0) return -1
  var step = direction < 0 ? -1 : 1
  for (var n = 1; n < count; n++) {
    var index = ((current + step * n) % count + count) % count
    if (hasMenu[index]) return index
  }
  return -1
}

if (typeof module !== "undefined") {
  module.exports = {
    appKind: appKind,
    itemNamed: itemNamed,
    replacementGlyph: replacementGlyph,
    primaryClickOpensMenu: primaryClickOpensMenu,
    monochrome: monochrome,
    warpConnectionIcon: warpConnectionIcon,
    hiddenRows: hiddenRows,
    cursorStops: cursorStops,
    adjacentMenu: adjacentMenu
  }
}
