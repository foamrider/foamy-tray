import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import ".." as Dev

// The dev (1.0.0) tray menu for foamy-kit's `render.py --trio` Before column:
// dev's TrayPopup fork with the same mock entries as Preview.qml, drawn with
// dev's row markup (30 px rows, bar font and foreground, nerd-font check,
// "‹"/"›" glyphs, hover fill, 45 % foreground border, 8 px padding). Dev had
// no keyboard cursor; the "cursor" state shows its pointer hover instead.
// Only used by the preview harness; the shell never loads it.
Item {
  id: preview
  required property QtObject bar
  required property Item anchorItem
  property var previewStates: ["menu", "cursor", "submenu", "long"]
  property string previewState: "menu"
  readonly property var popup: popup

  readonly property color foreground: Commons.Color.foreground
  readonly property string fontFamily: Style.font.family
  readonly property bool submenu: previewState === "submenu" || previewState === "long"
  readonly property string title: previewState === "long" ? "Stations" : "Friends"
  readonly property int hoverRow: previewState === "cursor" ? 3 : (previewState === "submenu" ? 0 : -1)

  function entry(text, extra) {
    var e = { text: text, icon: "", isSeparator: false, enabled: true, hasChildren: false, checkable: false, checked: false }
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
    entry("Online", { checkable: true, checked: true }), entry("Away", { checkable: true }),
    entry("Invisible", { checkable: true }), separator, entry("Show friends list")
  ]
  readonly property var longEntries: {
    var list = []
    for (var i = 1; i <= 40; i++) list.push(entry("Station " + i, { checkable: true, checked: i === 3 }))
    return list
  }
  readonly property var entries: previewState === "submenu" ? subEntries : previewState === "long" ? longEntries : rootEntries

  Dev.TrayPopup {
    id: popup
    anchorItem: preview.anchorItem
    bar: preview.bar
    open: true
    padding: Style.space(8)
    borderColor: Qt.rgba(preview.foreground.r, preview.foreground.g, preview.foreground.b, 0.45)
    contentWidth: popup.fittedContentWidth(Style.space(232))
    contentHeight: popup.fittedContentHeight((header.visible ? header.implicitHeight : 0) + rows.implicitHeight)
    // The fork has no cardItem and its default alias shadows contentItem:
    // the card is the parent of the content holder.
    property Item cardItem: menuColumn.parent ? menuColumn.parent.parent : null

    Column {
      id: menuColumn
      anchors.fill: parent

      Column {
        id: header
        visible: preview.submenu
        width: parent.width
        Item {
          width: parent.width
          implicitHeight: Style.space(30)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "‹"
            color: preview.foreground
            font.family: preview.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(28)
            text: preview.title
            color: preview.foreground
            font.family: preview.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
        Item {
          width: parent.width
          implicitHeight: Style.space(11)
          Rectangle {
            x: Style.space(10); width: parent.width - Style.space(20); height: 1
            anchors.verticalCenter: parent.verticalCenter
            color: Commons.Color.popups.border; opacity: 0.45
          }
        }
      }

      Item {
        width: parent.width
        height: parent.height - (header.visible ? header.implicitHeight : 0)
        clip: true
        Column {
          id: rows
          width: parent.width
          Repeater {
            model: preview.entries
            delegate: Item {
              id: row
              required property var modelData
              required property int index
              readonly property bool hiddenRow: !preview.submenu && ((index === 0 && modelData.hasChildren && modelData.text === "Steam")
                || (modelData.isSeparator && index <= 1))
              visible: !hiddenRow
              width: rows.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45
              Rectangle {
                visible: row.modelData.isSeparator
                x: Style.space(10); width: parent.width - Style.space(20); height: 1
                anchors.verticalCenter: parent.verticalCenter
                color: Commons.Color.popups.border; opacity: 0.45
              }
              Rectangle {
                visible: !row.modelData.isSeparator
                anchors.fill: parent
                radius: Style.cornerRadius * 2
                color: row.index === preview.hoverRow ? Style.hoverFillFor(preview.foreground, preview.foreground) : "transparent"
              }
              Text {
                visible: row.modelData.checkable
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: row.modelData.checked ? "\u{f00c}" : ""
                color: preview.foreground
                font.family: preview.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                visible: !row.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                x: Style.space(28)
                width: parent.width - x - Style.space(26)
                elide: Text.ElideRight
                text: row.modelData.text
                color: preview.foreground
                font.family: preview.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                visible: !row.modelData.isSeparator && row.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                text: "›"
                color: preview.foreground
                font.family: preview.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
