import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "kit"
import "TrayModel.js" as TrayModel

// One level of an app's tray menu, the body of the tray's FoamyPopupCard.
// Single cursor (FoamyCursor): Up/Down (j/k) move, Right (l) opens a
// submenu, Left (h) goes back, Enter/Space activate, Esc goes back one
// level and closes at the top, Tab/Shift-Tab open the next/previous app's
// menu. Pointer hover moves the same cursor, so only one row is lit.
//
// The menu entries (QsMenuEntry, or plain objects in the preview) and the
// level state belong to Tray.qml; this file only draws them and reports
// what the user asked for through the signals below.
PanelKeyCatcher {
  id: menu

  // QsMenuEntry-like objects: text, icon, isSeparator, enabled, hasChildren,
  // buttonType, checkState.
  property var entries: []
  property int depth: 0
  // The submenu's own title, shown in the pinned back row.
  property string title: ""
  // The app's title; a root entry that only repeats it is hidden.
  property string appTitle: ""
  // Ignore pointer clicks right after a level change (see Tray.qml).
  property bool pointerSettling: false

  readonly property bool atRoot: depth === 0
  readonly property var hidden: TrayModel.hiddenRows(entries, atRoot, appTitle)
  readonly property var stops: TrayModel.cursorStops(entries, hidden)
  // Inside a submenu, cursor stop 0 is the pinned back row.
  readonly property int backStops: atRoot ? 0 : 1
  readonly property alias cursor: cursor
  readonly property alias flick: flick
  property bool keyboardLevelChange: false

  signal back()
  signal enter(var entry, string title)
  signal trigger(var entry)
  signal dismiss()
  signal switchMenu(int direction)

  implicitWidth: FoamyStyle.menuWidth
  implicitHeight: header.shownHeight + list.implicitHeight

  FoamyCursor {
    id: cursor
    count: menu.stops.length + menu.backStops
  }

  function stopFor(row) {
    var i = stops.indexOf(row)
    return i < 0 ? -1 : i + backStops
  }

  function entryAt(stop) {
    if (stop < backStops || stop >= cursor.count) return null
    return entries[stops[stop - backStops]] || null
  }

  function activate(stop) {
    if (stop < 0) return
    if (stop < backStops) { goBack(); return }
    var entry = entryAt(stop)
    if (!entry) return
    if (entry.hasChildren) goInto(entry)
    else trigger(entry)
  }

  // Reset the scroll before the model swap: the swap destroys the row
  // delegates synchronously, so nothing may run on them afterwards.
  function goInto(entry) {
    wheel.scrollTo(0, false)
    enter(entry, String(entry.text || ""))
  }

  function goBack() {
    if (atRoot) return
    wheel.scrollTo(0, false)
    back()
  }

  function reset() {
    keyboardLevelChange = false
    cursor.reset()
    wheel.scrollTo(0, false)
  }

  // Keep the keyboard cursor's row inside the scrolled list.
  function reveal() {
    var entry = cursor.index - backStops
    if (entry < 0 || entry >= stops.length) return
    var row = rows.itemAt(stops[entry])
    if (!row) return
    if (row.y < flick.contentY) flick.contentY = row.y
    else if (row.y + row.height > flick.contentY + flick.height)
      flick.contentY = Math.min(flick.contentHeight - flick.height, row.y + row.height - flick.height)
  }

  onMoveRequested: function(dx, dy) {
    if (dy !== 0) {
      cursor.move(dy)
      reveal()
      return
    }
    keyboardLevelChange = true
    if (dx > 0) {
      var entry = entryAt(cursor.index)
      if (entry && entry.hasChildren) goInto(entry)
      else keyboardLevelChange = false
    } else if (!atRoot) {
      goBack()
    } else {
      keyboardLevelChange = false
    }
  }
  onActivateRequested: {
    keyboardLevelChange = true
    activate(cursor.index)
  }
  onCloseRequested: {
    if (atRoot) { dismiss(); return }
    keyboardLevelChange = true
    goBack()
  }
  onTabRequested: function(direction) { menu.switchMenu(direction) }

  // A level reached from the keyboard starts with its first entry lit; one
  // reached by pointer waits for the pointer, as on open.
  onDepthChanged: Qt.callLater(function() {
    if (menu.keyboardLevelChange && cursor.count > menu.backStops) cursor.index = menu.backStops
    else cursor.reset()
    menu.keyboardLevelChange = false
  })

  // Pinned above the list, so the way back stays reachable in a submenu
  // taller than the card. Only present below the root level.
  Column {
    id: header
    readonly property real shownHeight: visible ? implicitHeight : 0
    visible: !menu.atRoot
    width: menu.width
    spacing: 0

    FoamyCursorSurface {
      id: backRow
      width: header.width
      height: FoamyStyle.controlHeight
      foreground: FoamyPalette.text
      hasCursor: cursor.at(0) && !menu.atRoot
      onHovered: cursor.hover(0)
      onClicked: if (!menu.pointerSettling) menu.goBack()
      Accessible.role: Accessible.Button
      Accessible.name: FoamyI18n.t("Back")
      Accessible.description: menu.title

      FoamyIcon {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: (Style.space(24) - width) / 2
        width: FoamyStyle.font.subtitle
        height: width
        name: "chevron-left"
        color: FoamyPalette.text
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.space(28)
        anchors.right: parent.right
        anchors.rightMargin: FoamyStyle.rowPadding
        textFormat: Text.PlainText
        // Explicit, so a mirrored (RTL) card right-aligns it.
        horizontalAlignment: Text.AlignLeft
        text: menu.title
        color: FoamyPalette.text
        font.family: FoamyStyle.fontFamily
        font.pixelSize: FoamyStyle.font.bodySmall
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
    }

    Item {
      width: header.width
      height: FoamyStyle.gapLarge
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: FoamyStyle.rowPadding
        anchors.rightMargin: FoamyStyle.rowPadding
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: FoamyPalette.divider
      }
    }
  }

  // A wheel notch scrolls about three rows, however the mouse splits it.
  FoamyWheelScroll { id: wheel; target: flick }

  Flickable {
    id: flick
    y: header.shownHeight
    width: menu.width
    height: menu.height - header.shownHeight
    contentWidth: width
    contentHeight: list.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: list
      width: flick.width
      spacing: 0

      Repeater {
        id: rows
        model: menu.entries

        delegate: Item {
          id: row
          required property var modelData
          required property int index

          readonly property bool hiddenRow: !!menu.hidden[index]
          readonly property bool separator: !!modelData.isSeparator
          readonly property bool rowEnabled: modelData.enabled !== false
          readonly property int stop: menu.stopFor(index)
          readonly property string label: String(modelData.text || "")
          readonly property bool checkable: !separator && modelData.buttonType !== undefined
            && modelData.buttonType !== QsMenuButtonType.None
          readonly property bool checked: modelData.checkState === Qt.Checked

          visible: !hiddenRow
          width: list.width
          implicitHeight: hiddenRow ? 0 : (separator ? FoamyStyle.gapLarge : FoamyStyle.controlHeight)
          opacity: rowEnabled ? 1 : FoamyStyle.disabledOpacity

          Accessible.role: separator ? Accessible.Separator : Accessible.MenuItem
          Accessible.name: label
          Accessible.checkable: checkable
          Accessible.checked: checked

          Rectangle {
            visible: row.separator
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: FoamyStyle.rowPadding
            anchors.rightMargin: FoamyStyle.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: FoamyPalette.divider
          }

          FoamyCursorSurface {
            visible: !row.separator
            anchors.fill: parent
            foreground: FoamyPalette.text
            hasCursor: row.stop >= 0 && cursor.at(row.stop)
            // Separators and disabled entries don't react to the pointer.
            cursorShape: row.stop >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHovered: if (row.stop >= 0) cursor.hover(row.stop)
            onClicked: if (row.stop >= 0 && !menu.pointerSettling) menu.activate(row.stop)

            FoamyIcon {
              visible: row.checkable && row.checked
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: (Style.space(24) - width) / 2
              width: FoamyStyle.font.subtitle
              height: width
              name: "check"
              color: FoamyPalette.text
            }

            Image {
              id: entryIcon
              visible: String(row.modelData.icon || "") !== ""
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(24)
              width: Style.space(16)
              height: width
              fillMode: Image.PreserveAspectFit
              // Decode at physical pixels: IconImage uses the logical size,
              // which leaves PNG icons upscaled and blurry on HiDPI displays.
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: String(row.modelData.icon || "")
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: entryIcon.visible ? Style.space(46) : Style.space(28)
              anchors.right: submenuIcon.visible ? submenuIcon.left : parent.right
              anchors.rightMargin: submenuIcon.visible ? FoamyStyle.gap : FoamyStyle.rowPadding
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              text: row.label
              color: FoamyPalette.text
              font.family: FoamyStyle.fontFamily
              font.pixelSize: FoamyStyle.font.bodySmall
              elide: Text.ElideRight
            }

            FoamyIcon {
              id: submenuIcon
              visible: !!row.modelData.hasChildren
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: FoamyStyle.rowPadding
              width: FoamyStyle.font.subtitle
              height: width
              name: "chevron-right"
              color: FoamyPalette.secondaryText
            }
          }
        }
      }
    }
  }
}
