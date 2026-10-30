import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "kit"
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "foamy.tray"

  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  // The 4.5 bar puts its open-panel mark under this item: the icon whose
  // menu is open, not the middle of the whole tray.
  readonly property Item openPanelIndicatorItem: trayMenuOpen ? activeTrayAnchor : null
  // The open menu's card and its body (TrayMenu, built on first open).
  readonly property alias menuPopup: trayMenuPopup
  readonly property Item trayMenu: trayMenuPopup.bodyItem
  // The custom bar's reorder surface is above this widget's MouseAreas and
  // therefore owns the visible cursor while preserving the tray's own clicks.
  readonly property int barCursorShape: Qt.PointingHandCursor
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Passive items opt out through the status notifier protocol. No app is filtered by name.
  readonly property var trayItems: SystemTray.items.values.filter(function(item) {
    return item.status !== Status.Passive
  })
  readonly property int trayItemExtent: Style.bar.iconSlot

  // The 4.5 bar parents its tray-section widgets here. Keep them alongside the
  // app icons, with no drawer; older hosts simply leave this area empty.
  readonly property Item sectionHost: sectionArea
  readonly property string sectionEdge: "fixedEdge" in root && root.fixedEdge === "start" ? "start" : "end"
  readonly property bool sectionAtStart: sectionEdge === "end"
  readonly property bool sectionDragActive: !!bar && "traySectionDragActive" in bar && bar.traySectionDragActive === true
  readonly property int sectionCount: bar && bar.layoutConfig && Array.isArray(bar.layoutConfig.tray)
    ? bar.layoutConfig.tray.length : 0
  readonly property real sectionExtent: root.vertical ? sectionArea.height : sectionArea.width
  readonly property var sectionShown: sectionExtent > 0
    ? { x: sectionArea.x, y: sectionArea.y, width: sectionArea.width, height: sectionArea.height } : null

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    // The cursor starts unlit again, as on any open.
    if (trayMenuPopup.bodyItem) trayMenuPopup.bodyItem.reset()
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item) return
    if (!item.menu) {
      if (!mouse) return
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    var switching = trayMenuOpen && activeTrayAnchor !== anchorItem
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
    // An open card moving to another icon needs a new anchor rect.
    if (switching) Qt.callLater(function() { trayMenuPopup.anchor.updateAnchor() })
    focusTrayMenu()
  }

  // Keys reach the menu once the focus grab hands the card keyboard focus.
  function focusTrayMenu() {
    var menu = trayMenuPopup.ensureBody()
    if (menu && trayMenuOpen) menu.forceActiveFocus()
  }

  // The tray's icon delegates, in bar order.
  function trayAnchor(index) {
    return trayIcons.itemAt(index)
  }

  // Tab/Shift-Tab in a menu: open the next/previous app's menu. The host's
  // panel order skips the tray (it has no panel of its own), so this is
  // the adjacent panel a menu can switch to.
  function switchTrayMenu(direction) {
    var current = trayItems.indexOf(activeTrayItem)
    var hasMenu = trayItems.map(function(item) { return !!item.menu })
    var next = TrayModel.adjacentMenu(hasMenu, current, direction)
    if (next < 0 || !trayAnchor(next)) return false
    openTrayMenu(trayItems[next], trayAnchor(next), null)
    return true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to Image; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  // The 4.5 host only creates section delegates while their parent is visible.
  // Count configured entries too, so an icon-free tray can bootstrap its children.
  visible: trayItems.length > 0 || sectionCount > 0 || sectionExtent > 0
  implicitWidth: root.vertical ? root.barSize : trayItems.length * trayItemExtent + sectionExtent
  implicitHeight: root.vertical ? trayItems.length * trayItemExtent + sectionExtent : root.barSize

  Item {
    id: sectionArea
    // An empty section needs a drop target while dragging. Otherwise it takes
    // no space. Allow for the host's half-bar-size drop inset at both ends.
    // Children determine size, avoiding a parent/child size loop.
    implicitWidth: root.vertical ? (childrenRect.height > 0 || root.sectionDragActive ? root.barSize : 0)
      : Math.max(childrenRect.width, root.sectionDragActive ? root.barSize * 2 : 0)
    implicitHeight: root.vertical ? Math.max(childrenRect.height, root.sectionDragActive ? root.barSize * 2 : 0)
      : (childrenRect.width > 0 || root.sectionDragActive ? root.barSize : 0)
    x: root.vertical || root.sectionAtStart ? 0 : root.trayItems.length * root.trayItemExtent
    y: !root.vertical || root.sectionAtStart ? 0 : root.trayItems.length * root.trayItemExtent
  }

  Repeater {
    id: trayIcons
    model: root.trayItems
    TrayItem {
      required property int index
      x: root.vertical ? (root.barSize - width) / 2
        : index * root.trayItemExtent + (root.sectionAtStart ? root.sectionExtent : 0)
      y: root.vertical ? index * root.trayItemExtent + (root.sectionAtStart ? root.sectionExtent : 0)
        : (root.barSize - height) / 2
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  FoamyPopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // Menus are denser than panels: the stock tray's 8 px card padding.
    padding: FoamyStyle.gap
    // The card fades out after `open` drops (it stays visible until the
    // fade ends), so resetting on "open" would swap a live submenu for the
    // root menu mid-fade: a visible flash, and a resize/reposition if the
    // two have different geometry. Wait for the fade to actually finish.
    // Switching to a different tray item still resets immediately, from
    // openTrayMenu() itself.
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    // Ordinary tray menus may use the available screen height (the card caps
    // itself there), so Steam doesn't scroll when every row fits.
    onOpenChanged: if (open) Qt.callLater(root.focusTrayMenu)

    body: Component {
      TrayMenu {
        entries: root.currentChildren ? root.currentChildren.values : []
        depth: root.submenuDepth
        title: root.currentTitle
        appTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
        pointerSettling: root.menuLevelSettling
        onBack: root.leaveSubmenu()
        onEnter: function(entry, title) { root.enterSubmenu(entry, title) }
        onTrigger: function(entry) {
          entry.triggered()
          root.close()
        }
        onDismiss: root.close()
        onSwitchMenu: function(direction) { root.switchTrayMenu(direction) }
      }
    }
  }

  // Recolor symbolic icons and known monochrome app assets, preserving their
  // status-specific shapes while keeping them visible on either theme.
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    property bool monochrome: false
    property bool attention: false
    readonly property bool recolor: monochrome || root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size,
      // which leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: !trayIconRoot.recolor
      layer.enabled: trayIconRoot.recolor
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.recolor
      colorization: 1.0
      colorizationColor: root.foreground
    }

    Rectangle {
      visible: trayIconRoot.attention
      anchors.top: parent.top
      anchors.right: parent.right
      width: parent.width / 3
      height: width
      radius: width / 2
      color: Commons.Color.urgent
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData
    readonly property string connectionIcon: TrayModel.warpConnectionIcon(modelData)
    // Special cases are matched by the item's id or title (TrayModel.js),
    // never by its tooltip.
    readonly property string replacementGlyph: TrayModel.replacementGlyph(modelData)
    readonly property bool useReplacementGlyph: replacementGlyph !== ""
    readonly property bool primaryClickOpensMenu: TrayModel.primaryClickOpensMenu(modelData)

    // trayItems already leaves passive items out.
    implicitWidth: root.trayItemExtent
    implicitHeight: root.trayItemExtent

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    TrayIcon {
      anchors.centerIn: parent
      visible: !trayItemRoot.useReplacementGlyph
      width: Style.space(12)
      height: Style.space(12)
      icon: trayItemRoot.connectionIcon
      attention: trayItemRoot.connectionIcon !== String(trayItemRoot.modelData.icon || "")
      // WARP ships white PNGs without a symbolic icon name.
      monochrome: TrayModel.monochrome(trayItemRoot.modelData)
    }

    OpticalGlyph {
      anchors.centerIn: parent
      visible: trayItemRoot.useReplacementGlyph
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      text: trayItemRoot.replacementGlyph
      fontFamily: root.fontFamily
      fontSize: Style.font.body
      color: root.foreground
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        // Configured menu launchers use the same surface on left and right click.
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.primaryClickOpensMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
