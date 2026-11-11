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

// Apps that hide their window to the tray and whose Activate does nothing
// (libayatana-appindicator items such as Spotify). Left-click brings the
// window back: focus it when it is mapped, otherwise trigger the app's own
// menu entry that shows it. Matched like APPS, by Id then Title.
var WINDOW_APPS = {
  spotify: { names: ["spotify"], windowClass: "spotify", showEntry: "show spotify" }
}

function windowApp(item) {
  if (!item) return null
  var fields = [item.id, item.title]
  for (var f = 0; f < fields.length; f++) {
    for (var kind in WINDOW_APPS) {
      var app = WINDOW_APPS[kind]
      for (var n = 0; n < app.names.length; n++) {
        if (nameMatches(fields[f], app.names[n])) return app
      }
    }
  }
  return null
}

// The app's window among `windows` ({ wmClass, address, focusOrder }): the
// most recently focused one with the app's class, or null. The result's
// address always has its 0x prefix (Quickshell reports it without one).
function appWindow(app, windows) {
  if (!app) return null
  var found = null
  for (var i = 0; i < (windows || []).length; i++) {
    var win = windows[i] || {}
    if (text(win.wmClass) !== app.windowClass) continue
    var address = String(win.address || "").replace(/^0x/i, "")
    if (!/^[0-9a-f]+$/i.test(address)) continue
    if (!found || Number(win.focusOrder) < Number(found.focusOrder))
      found = { wmClass: win.wmClass, address: "0x" + address, focusOrder: win.focusOrder }
  }
  return found
}

// Index of the menu entry that shows the app's window, or -1.
function showWindowEntry(app, entries) {
  if (!app) return -1
  for (var i = 0; i < (entries || []).length; i++) {
    var entry = entries[i] || {}
    if (!entry.isSeparator && entry.enabled !== false && text(entry.text) === app.showEntry) return i
  }
  return -1
}

// A glyph from the widget's `glyphs` setting in shell.json: an object from
// app name to glyph, matched like APPS (Id, then Title), e.g.
// { "spotify": "\u{f1bc}" }. Empty when nothing matches.
function customGlyph(item, glyphs) {
  if (!item || !glyphs || typeof glyphs !== "object" || Array.isArray(glyphs)) return ""
  var fields = [item.id, item.title]
  for (var f = 0; f < fields.length; f++) {
    for (var name in glyphs) {
      var glyph = glyphs[name]
      if (typeof glyph !== "string" || glyph.trim() === "") continue
      if (nameMatches(fields[f], text(name))) return glyph.trim()
    }
  }
  return ""
}

// Theme-aware Nerd Font glyphs for low-contrast tray bitmaps; the user's
// `glyphs` setting wins over the built-in ones.
function replacementGlyph(item, glyphs) {
  var custom = customGlyph(item, glyphs)
  if (custom !== "") return custom
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

// The bar tooltip for a tray item: its tooltip title, else its Title or Id.
// All three come from the app, and the host draws the text unwrapped, one
// line per newline, in a popup sized to fit it: a 20,000-character title
// made a 160,000 px wide tooltip and about 550 MB of buffer on hover. Keep
// at most TOOLTIP_LINES lines of TOOLTIP_LINE_CHARS characters, far more
// than any real tray tooltip uses, and end a cut line with an ellipsis so
// the cut shows. The text is sliced before it is split, so an oversized
// title is never scanned whole.
var TOOLTIP_LINES = 8
var TOOLTIP_LINE_CHARS = 160

// The first `length` characters of `value`, without half a surrogate pair.
function clip(value, length) {
  if (value.length <= length) return value
  var code = value.charCodeAt(length - 1)
  return value.slice(0, code >= 0xd800 && code <= 0xdbff ? length - 1 : length)
}

function tooltipText(item) {
  if (!item) return ""
  var full = String(item.tooltipTitle || item.title || item.id || "")
  var budget = TOOLTIP_LINES * (TOOLTIP_LINE_CHARS + 2)
  var lines = full.slice(0, budget).split(/\r\n|\r|\n/)
  var more = full.length > budget || lines.length > TOOLTIP_LINES
  lines = lines.slice(0, TOOLTIP_LINES)
  for (var i = 0; i < lines.length; i++) {
    var line = clip(lines[i], TOOLTIP_LINE_CHARS)
    var last = i === lines.length - 1
    if (line.length < lines[i].length || (last && more)) line += "\u2026"
    lines[i] = line
  }
  return lines.join("\n")
}

// A menu entry's label on one line. Labels come from the app and may hold
// line breaks; a row draws one line of text, so a break would spill the
// rest over the neighbouring rows. Breaks become spaces and the row elides
// whatever does not fit.
function menuLabel(value) {
  return String(value === undefined || value === null ? "" : value).replace(/\s*[\r\n\u2028\u2029]+\s*/g, " ")
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
    windowApp: windowApp,
    appWindow: appWindow,
    showWindowEntry: showWindowEntry,
    customGlyph: customGlyph,
    replacementGlyph: replacementGlyph,
    primaryClickOpensMenu: primaryClickOpensMenu,
    monochrome: monochrome,
    warpConnectionIcon: warpConnectionIcon,
    tooltipText: tooltipText,
    menuLabel: menuLabel,
    TOOLTIP_LINES: TOOLTIP_LINES,
    TOOLTIP_LINE_CHARS: TOOLTIP_LINE_CHARS,
    hiddenRows: hiddenRows,
    cursorStops: cursorStops,
    adjacentMenu: adjacentMenu
  }
}
