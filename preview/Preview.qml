import QtQuick
import Quickshell
import "../kit"
import ".." as Plugin

// Preview states for the foamy-kit preview harness (see foamy-kit README):
// the tray menu card with mock entries (no D-Bus, no processes). The real
// menus, in the hosts' real bars, are captured by tests/runtime.py --shots.
Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  property var previewStates: ["menu", "cursor", "submenu", "long"]
  property string previewState: "menu"
  // FoamyPopupCard is a window, not an Item.
  readonly property var popup: popup

  function entry(text, extra) {
    var e = { text: text, icon: "", isSeparator: false, enabled: true, hasChildren: false,
      buttonType: QsMenuButtonType.None, checkState: Qt.Unchecked }
    for (var key in extra || {}) e[key] = extra[key]
    return e
  }
  readonly property var separator: entry("", { isSeparator: true })
  readonly property var rootEntries: [
    entry("Steam", { hasChildren: true }), separator,
    entry("Store"), entry("Library"), entry("Community"), separator,
    entry("Recent games", { hasChildren: true }), entry("Friends", { hasChildren: true }), separator,
    entry("Offline mode", { enabled: false }), entry("Exit Steam")
  ]
  readonly property var subEntries: [
    entry("Online", { buttonType: QsMenuButtonType.RadioButton, checkState: Qt.Checked }),
    entry("Away", { buttonType: QsMenuButtonType.RadioButton }),
    entry("Invisible", { buttonType: QsMenuButtonType.RadioButton }),
    separator,
    entry("Show friends list")
  ]
  readonly property var longEntries: {
    var list = []
    for (var i = 1; i <= 40; i++) list.push(entry("Station " + i, { buttonType: QsMenuButtonType.RadioButton, checkState: i === 3 ? Qt.Checked : Qt.Unchecked }))
    return list
  }

  FoamyPopupCard {
    id: popup
    anchorItem: preview.anchorItem
    bar: preview.bar
    open: true
    body: Component {
      Plugin.TrayMenu {
        depth: preview.previewState === "submenu" || preview.previewState === "long" ? 1 : 0
        title: preview.previewState === "long" ? "Stations" : "Friends"
        appTitle: "Steam"
        entries: preview.previewState === "submenu" ? preview.subEntries
          : preview.previewState === "long" ? preview.longEntries : preview.rootEntries
      }
    }
  }

  onPreviewStateChanged: Qt.callLater(function() {
    var menu = popup.bodyItem
    if (!menu) return
    menu.reset()
    if (preview.previewState === "cursor") { menu.cursor.index = 1 }
    if (preview.previewState === "submenu") { menu.cursor.index = 1 }
  })
}
