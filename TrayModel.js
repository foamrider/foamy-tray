function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function warpConnectionIcon(item) {
  var icon = String(item && item.icon || "")
  if (!itemNamed(item, "warp") && !itemNamed(item, "cloudflare")) return icon
  // WARP bakes a red badge into its attention PNGs. Render that badge separately
  // so tinting the white connection shape cannot erase the notification color.
  return icon.replace(/\/attention(_disconnected)?\.png(?=\?|$)/, function(match, disconnected) {
    return disconnected ? "/disconnected.png" : "/connected.png"
  })
}

if (typeof module !== "undefined") {
  module.exports = { itemNamed: itemNamed, warpConnectionIcon: warpConnectionIcon }
}
