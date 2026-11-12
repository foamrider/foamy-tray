import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "harness"
import "hostbar" as Host
import "plugin" as Foamy
import "plugin/kit"
import "plugin/TrayModel.js" as TrayModel
import "plugin/kit/FoamyText.js" as FoamyText

// Offscreen integration test, run by tests/runtime.py: the host's real
// Bar.qml (Omarchy 4.5) hosts Foamy Tray, and four synthetic apps on a
// private D-Bus session supply tray items and DBusMenus. Covers the
// tray-section hooks (sectionHost, sectionEdge, sectionShown, tray layout,
// drag drop target), passive items, the open-panel mark, and the menu's
// keyboard cursor, submenus, Esc, Tab between app menus and activation, and
// right-click on an app without a DBusMenu.
ShellRoot {
  id: test
  property int checks: 0
  property int stage: 0
  property int orientation: 0
  property var positions: ["top", "left", "bottom", "right"]
  property var savedProbe: null
  property var savedTray: null
  property real markCenter: 0
  property int first: 0
  property int second: 1
  property int spotify: -1
  property int plain: -1
  readonly property string shots: Quickshell.env("FOAMY_TRAY_SHOTS") || ""
  readonly property string theme: Quickshell.env("FOAMY_TRAY_THEME") || "dark"

  // Stages run back to back. A stage whose check needs an asynchronous
  // result (the fixture's status poll, a D-Bus round trip, the bar's
  // relayout) gates on it with settle(): when the condition is not true yet,
  // the stage runs again once it is, or fails after `settleMs`.
  readonly property int settleMs: 15000
  property bool waiting: false
  FoamyWait {
    id: wait
  }
  function settle(condition, message) {
    if (condition())
      return check(true, message)
    stage--
    waiting = true
    wait.waitFor(condition, settleMs, function (ok) {
      waiting = false
      if (ok)
        driver.restart()
      else
        check(false, message + " (not true after " + settleMs + " ms)")
    })
    return false
  }
  function check(ok, message) {
    if (!ok) {
      finished = true
      console.log("FOAMY FAIL " + positions[orientation] + ": " + message)
      Qt.exit(1)
      return false
    }
    checks++
    console.log("PASS: " + positions[orientation] + ": " + message)
    return true
  }
  function configure(section, hasWidget, hasTray) {
    var layout = {
      left: [],
      center: [],
      right: [],
      tray: []
    }
    if (hasTray !== false)
      layout[section].push("foamy.tray")
    if (hasWidget)
      layout.tray = [
        {
          id: "test.widget",
          label: "Hosted widget",
          extent: 120
        }
      ]
    bar.barConfig = {
      position: positions[orientation],
      background: "opaque",
      layout: layout
    }
  }
  function tray() {
    return bar.moduleWidgets("foamy.tray")[0]
  }
  function widget() {
    return bar.moduleWidgets("test.widget")[0]
  }
  function slotFor(id) {
    for (var i = 0; i < bar.moduleSlots.length; i++)
      if (bar.moduleSlots[i].activeItem && bar.moduleSlots[i].activeItem.moduleName === id)
        return bar.moduleSlots[i]
    return null
  }
  // SystemTray doesn't keep registration order: find the apps by id.
  function appIndex(t, id) {
    for (var i = 0; i < t.trayItems.length; i++)
      if (t.trayItems[i].id === id)
        return i
    return -1
  }
  function inside(item, ancestor) {
    for (var p = item; p; p = p.parent)
      if (p === ancestor)
        return true
    return false
  }
  function eventLog() {
    events.reload()
    events.waitForJob()
    return events.text()
  }
  // Screenshots (tests/runtime.py --shots): the bar window and the menu card,
  // composed by the script at the card's anchor rect.
  function shot(name) {
    if (!shots)
      return
    var t = tray()
    var barWindow = t.QsWindow.window
    var popup = t.menuPopup
    // The window's own contentItem can't be grabbed; its largest QML child
    // (the bar's loader) spans it.
    var kids = barWindow.contentItem.children
    var surface = null
    for (var i = 0; i < kids.length; i++)
      if (!surface || kids[i].width * kids[i].height > surface.width * surface.height)
        surface = kids[i]
    var at = surface.mapToItem(null, 0, 0)
    surface.grabToImage(function (barImage) {
      var barPath = shots + "/" + name + "-bar.png";
      barImage.saveToFile(barPath)
      var card = popup.cardItem
      if (!t.trayMenuOpen || !card) {
        console.log("FOAMY SHOT " + name + " " + barPath + " - 0 0 " + Math.round(at.x) + " " + Math.round(at.y))
        return
      }
      card.grabToImage(function (cardImage) {
        var cardPath = shots + "/" + name + "-card.png";
        cardImage.saveToFile(cardPath)
        var origin = card.mapToItem(null, 0, 0)
        console.log("FOAMY SHOT " + name + " " + barPath + " " + cardPath + " " + Math.round(popup.anchor.rect.x + origin.x) + " " + Math.round(popup.anchor.rect.y + origin.y) + " " + Math.round(at.x) + " " + Math.round(at.y))
      })
    })
  }

  Component {
    id: trayComponent
    Foamy.Tray {}
  }
  Component {
    id: widgetComponent
    BarWidget {
      id: probe
      implicitWidth: vertical ? barSize : setting("extent", 120)
      implicitHeight: vertical ? setting("extent", 120) : barSize
      property bool opened: false
      function open() {
        opened = true
      }
      function close() {
        opened = false
      }
      Rectangle {
        anchors.fill: parent
        color: Commons.Color.popups.background
        border.color: Commons.Color.popups.border
        Text {
          anchors.centerIn: parent
          text: probe.setting("label", "Widget")
          rotation: probe.vertical ? 90 : 0
          color: Commons.Color.popups.text
          font.pixelSize: 12
        }
      }
      PopupCard {
        anchorItem: probe
        bar: probe.bar
        owner: probe
        open: probe.opened
        triggerMode: "hover"
        contentWidth: 180
        contentHeight: 60
        Text {
          text: "Hosted panel"
          color: Commons.Color.popups.text
        }
      }
    }
  }
  QtObject {
    id: registry
    property int revision: 0
    property var widgets: ({
        "foamy.tray": {
          component: trayComponent
        },
        "test.widget": {
          component: widgetComponent
        }
      })
    function metadataFor(id) {
      return {
        firstParty: false
      }
    }
  }
  Loader {
    id: host
    source: Qt.resolvedUrl("hostbar/Bar.qml")
    onLoaded: {
      item.barWidgetRegistry = registry
      test.configure("right", true)
      driver.start()
    }
  }
  readonly property var bar: host.item
  // The host's tooltip label font (plugins/bar/Bar.qml tooltipLabel).
  TextMetrics {
    id: tooltipMetrics
    font.pixelSize: Style.font.body
  }
  FileView {
    id: status
    path: Quickshell.env("FOAMY_TRAY_STATUS")
  }
  FileView {
    id: events
    path: Quickshell.env("FOAMY_TRAY_EVENTS")
    blockLoading: true
    printErrors: false
  }
  readonly property var lightTheme: ({
      "bar.background": "#fafafa",
      "bar.text": "#202020",
      "popups.background": "#fafafa",
      "popups.text": "#202020",
      "popups.border": "#404040"
    })

  // One stage per turn of the event loop, so bindings and signals settle in between.
  Timer {
    id: driver
    interval: 1
    onTriggered: test.runStage()
  }
  property bool finished: false
  function runStage() {
    var t = test.tray()
    var m = t ? t.trayMenu : null
    switch (test.stage++) {
    case 0:
      test.check(!!t, "real host loads the tray")
      test.check(t.trayItems.length === 0, "private bus starts without active app icons")
      test.check(!!test.widget() && t.visible && t.sectionExtent === 120, "tray section renders with no app icons")
      test.check(test.widget().settings.label === "Hosted widget", "host injects section widget settings")
      test.check(test.inside(test.widget(), t.sectionHost), "host draws section widgets inside sectionHost")
      test.check(t.sectionShown && t.sectionShown.width > 0 && t.sectionShown.height > 0, "section exposes visible geometry")
      test.savedProbe = test.widget()
      test.savedTray = t
      test.widget().open()
      break
    case 1:
      test.check(test.widget().opened && bar.traySectionPopoutOpen && t.visible, "hosted popup keeps its visible anchor")
      test.widget().close()
      status.setText("Active\n")
      break
    case 2:
      if (!test.settle(function () {
        return t.trayItems.length === 1 && t.visible
      }, "active application icon joins hosted widget"))
        break
      test.check((t.vertical ? t.implicitHeight : t.implicitWidth) === 120 + t.trayItemExtent, "app and hosted sizes add without overlap")
      test.check(t.sectionHost.x === 0 && t.sectionHost.y === 0, "end-fixed tray keeps app at its fixed edge")
      test.check(slotFor("foamy.tray").hostsTraySection === true, "bar treats the tray as the tray-section host")
      test.configure("left", true)
      break
    case 3:
      test.check(t === test.savedTray && test.widget() === test.savedProbe, "moving tray preserves hosted widget instances")
      test.check(t.sectionEdge === "start", "start-fixed tray forwards its growth edge")
      test.check((t.vertical ? t.sectionHost.y : t.sectionHost.x) === t.trayItemExtent, "start-fixed tray puts section after app icons")
      Commons.Color.shellValues = test.lightTheme
      break
    case 4:
      test.check(t.foreground.r < 0.5, "tray icons follow a light bar's foreground")
      Commons.Color.shellValues = {}
      test.configure("left", false)
      break
    case 5:
      test.check(t.sectionExtent === 0 && t.trayItems.length === 1 && t.visible, "removing hosted widgets leaves app icons")
      status.setText("Passive\n")
      break
    case 6:
      if (!test.settle(function () {
        return !t.visible && t.sectionExtent === 0
      }, "empty tray takes no space outside a drag"))
        break
      // Exercise the actual bar's geometry and drop-target code without persisting a move.
      bar.barConfig = {
        position: test.positions[test.orientation],
        background: "opaque",
        layout: {
          left: ["foamy.tray"],
          center: [],
          right: [
            {
              id: "test.widget",
              extent: 80
            }
          ],
          tray: []
        }
      }
      test.stage = 18
      break
    case 7:
      test.check(t.visible && t.sectionExtent >= t.trayItemExtent, "drag exposes empty section drop target")
      var point = t.sectionHost.mapToItem(null, t.sectionHost.width / 2, t.sectionHost.height / 2)
      var target = bar.moduleDropAtScene(point, test.slotFor("test.widget"))
      test.check(target && target.region === "tray", "real bar detects a drop into empty section")
      bar.clearBarDrag()
      test.configure("right", true)
      break
    case 8:
      test.check(t.visible && test.widget(), "hosted widget reappears after drag")
      test.configure("right", true, false)
      break
    case 9:
      test.check(!test.tray() && !test.widget(), "removing tray releases hosted widgets")
      test.configure("right", true)
      break
    case 10:
      test.check(test.tray() && test.widget(), "re-adding tray restores hosted widgets")
      test.savedProbe = null
      test.savedTray = null
      test.nextOrientation()
      break
    case 18:
      bar.beginBarDrag(test.slotFor("test.widget"), 5, 5)
      test.stage = 7
      break

    // --- menus (top bar) ---------------------------------------------------------------
    case 30:
      if (test.theme === "light")
        Commons.Color.shellValues = test.lightTheme
      // Screenshots use Hyprland's common 6 px rounding (foamy doubles it).
      if (test.shots)
        Style.cornerRadius = 6
      status.setText("Active\nActive\n")
      break
    case 31:
      if (!test.settle(function () {
        test.first = test.appIndex(t, "foamy-test")
        test.second = test.appIndex(t, "foamy-second")
        return t.trayItems.length === 2 && test.first >= 0 && test.second >= 0 && !!t.trayItems[test.first].menu
      }, "two apps with menus are shown"))
        break
      test.check(!t.trayMenu, "menu body is not built before the first open")
      test.check(t.trayTooltip(t.trayItems[test.first]) === "Test app", "an app without a tooltip shows its title")
      // The host sizes its tooltip popup to the text: the second app's
      // 20,000-character title would make it about 160,000 px wide.
      var tip = t.trayTooltip(t.trayItems[test.second])
      var tipLines = tip.split("\n")
      var widest = 0
      for (var i = 0; i < tipLines.length; i++) {
        tooltipMetrics.text = tipLines[i]
        widest = Math.max(widest, tooltipMetrics.width)
      }
      test.check(tip.indexOf("<b>Second</b> AAA") === 0 && tipLines.length <= FoamyText.TOOLTIP_LINES && tipLines.every(function (line) {
        return line.length <= FoamyText.TOOLTIP_CHARS
      }) && widest < 1920, "an oversized app tooltip is bounded: " + tipLines.length + " lines, " + tip.length + " chars, " + widest + " px")
      test.check(TrayModel.replacementGlyph({
        id: "steam"
      }) === String.fromCharCode(0xf1b6) && TrayModel.replacementGlyph({
        id: "remmina-icon"
      }) === String.fromCharCode(0xeb3a), "escaped Nerd Font glyphs survive in the QML engine")
      t.openTrayMenu(t.trayItems[test.first], t.trayAnchor(test.first))
      break
    case 32:
      if (!test.settle(function () {
        m = t.trayMenu
        return t.trayMenuOpen && !!m && m.entries.length === 5
      }, "menu opens with the app's DBusMenu entries"))
        break
      test.check(JSON.stringify(m.stops) === "[0,2,4]", "cursor skips the separator and the disabled entry")
      test.check(m.cursor.index === -1, "no row is lit on open")
      // Menu text is the kit menu's size (FoamyMenu: body), in logical
      // pixels, so it follows the font scale and the monitor's scaling.
      var sizes = [];
      (function walk(item) {
          if (item.text !== undefined && item.font !== undefined && item.text === "Stations")
            sizes.push(item.font.pixelSize)
          for (var i = 0; i < item.children.length; i++)
            walk(item.children[i])
        })(m)
      test.check(sizes.length === 1 && sizes[0] === FoamyStyle.font.body, "menu text is the kit menu's size: " + sizes)
      var labels = [];
      (function walk(item) {
          if (item.lineCount !== undefined && String(item.text).indexOf("Offline mode") === 0)
            labels.push(item)
          for (var i = 0; i < item.children.length; i++)
            walk(item.children[i])
        })(m)
      test.check(labels.length === 1 && labels[0].lineCount === 1 && labels[0].height <= FoamyStyle.controlHeight && labels[0].text === "Offline mode second line third line", "a multi-line app label stays on its row: " + labels.map(function (l) {
        return l.lineCount + " lines, " + l.height + " px"
      }))
      test.check(t.openPanelIndicatorItem === t.trayAnchor(test.first), "open-panel mark targets the clicked icon")
      var slot = test.slotFor("foamy.tray")
      test.check(slot.panelIndicatorItem === t.trayAnchor(test.first), "the bar reads openPanelIndicatorItem")
      test.markCenter = slot.panelIndicatorCenter
      test.check(t.menuPopup.cardItem && t.menuPopup.cardItem.radius === Style.cornerRadius * 2, "card uses the foamy radius")
      test.check(t.menuPopup.borderSpec && Border.uniformWidth(t.menuPopup.borderSpec) === 1, "card uses the foamy 1px border")
      test.check(t.menuPopup.padding === Style.space(8), "card uses the kit's 8 px menu padding")
      test.shot("menu")
      break
    case 33:
      m.moveRequested(0, 1)
      m.moveRequested(0, 1)
      test.check(m.cursor.index === 1 && m.entryAt(m.cursor.index).text === "Stations", "Down moves the single cursor")
      test.shot("menu-cursor")
      break
    case 34:
      m.moveRequested(1, 0)
      break
    case 35:
      // The submenu's entries come from the app over D-Bus.
      if (!test.settle(function () {
        return t.submenuDepth === 1 && m.title === "Stations" && m.entries.length === 2
      }, "Right opens the submenu"))
        break
      test.check(m.cursor.index === 1, "a submenu opened from the keyboard lights its first entry")
      test.check(m.entries[1].checkState === Qt.Checked && m.entries[0].buttonType === QsMenuButtonType.RadioButton, "radio entries keep their check state")
      test.shot("submenu")
      break
    case 36:
      m.closeRequested()
      test.check(t.submenuDepth === 0 && t.trayMenuOpen, "Esc in a submenu goes back one level")
      m.tabRequested(1)
      break
    case 37:
      if (!test.settle(function () {
        return m.entries.length === 1 && m.entries[0].text === "Second action" && m.cursor.index === -1
      }, "the next menu starts at its top, unlit"))
        break
      test.check(t.activeTrayItem === t.trayItems[test.second] && t.openPanelIndicatorItem === t.trayAnchor(test.second), "Tab opens the next app's menu")
      test.check(Math.abs(Math.abs(test.slotFor("foamy.tray").panelIndicatorCenter - test.markCenter) - t.trayItemExtent) < 1, "the mark moves under the icon whose menu is open")
      test.shot("tab")
      break
    case 38:
      m.tabRequested(-1)
      test.check(t.activeTrayItem === t.trayItems[test.first], "Shift-Tab goes back to the previous app's menu")
      break
    case 39:
      // The first app's entries load again over D-Bus after the switch.
      if (!test.settle(function () {
        return m.entries.length === 5 && m.entryAt(0).text === "Open window"
      }, "Shift-Tab shows the previous app's entries again"))
        break
      m.moveRequested(0, 1)
      m.activateRequested()
      break
    case 40:
      test.check(!t.trayMenuOpen, "activating an entry closes the menu")
      break
    case 41:
      if (!test.settle(function () {
        return test.eventLog().indexOf("/org/foamy/One 1 clicked") !== -1
      }, "Enter sends the entry's click to the app"))
        break
      t.openTrayMenu(t.trayItems[test.first], t.trayAnchor(test.first))
      break
    case 42:
      test.check(t.trayMenuOpen && t.submenuDepth === 0 && m.cursor.index === -1, "reopening starts unlit at the top")
      m.closeRequested()
      break
    case 43:
      test.check(!t.trayMenuOpen, "Esc at the top level closes the menu")
      t.openTrayMenu(t.trayItems[test.first], t.trayAnchor(test.first))
      break
    case 44:
      test.check(t.trayMenuOpen && t.activeTrayItem === t.trayItems[test.first], "the first app's menu is open again")
      // The app turns passive (or quits) while its menu is open.
      status.setText("Passive\nActive\n")
      break
    case 45:
      if (!test.settle(function () {
        return t.trayItems.length === 1 && !t.trayMenuOpen
      }, "a menu closes when its app's icon goes away"))
        break
      status.setText("Active\nActive\nActive\n")
      break
    case 46:
      test.settle(function () {
        test.spotify = test.appIndex(t, "spotify-client")
        return test.spotify >= 0 && !!t.trayAnchor(test.spotify)
      }, "a Spotify-like app hidden to the tray is shown")
      break
    case 47:
      // Its menu loads over D-Bus after the icon shows; a click before that
      // falls back to Activate.
      if (!test.settle(function () {
        var anchor = t.trayAnchor(test.spotify)
        return TrayModel.showWindowEntry(anchor.windowApp, anchor.windowAppEntries) >= 0
      }, "its Show Spotify entry is loaded"))
        break
      // No Hyprland window offscreen, so the click goes to its "Show Spotify" entry.
      t.trayAnchor(test.spotify).primaryClick()
      break
    case 48:
      if (!test.settle(function () {
        return test.eventLog().indexOf("/org/foamy/Spotify 3 clicked") !== -1
      }, "left-click on Spotify triggers Show Spotify"))
        break
      test.check(test.eventLog().indexOf("/org/foamy/Spotify - activate") === -1 && !t.trayMenuOpen, "and neither sends Activate nor opens the menu")
      status.setText("Active\nActive\nActive\nActive\n")
      break
    case 49:
      if (!test.settle(function () {
        test.plain = test.appIndex(t, "foamy-plain")
        return test.plain >= 0 && !!t.trayAnchor(test.plain)
      }, "an app without a DBusMenu is shown"))
        break
      test.check(!t.trayItems[test.plain].hasMenu && !t.trayItems[test.plain].menu, "and Quickshell reports no menu for it")
      // Right-click goes through the same path as the MouseArea's press.
      t.trayAnchor(test.plain).displayMenu()
      test.check(!t.trayMenuOpen && !t.menuPopup.open, "right-click on it opens no menu card")
      // A middle-click after it: D-Bus keeps one connection's calls in
      // order, so any call the right-click made arrives before this one.
      t.trayItems[test.plain].secondaryActivate()
      break
    case 50:
      if (!test.settle(function () {
        return test.eventLog().indexOf("/org/foamy/Plain - secondary-activate") !== -1
      }, "a middle-click on it reaches the app"))
        break
      var plainLog = test.eventLog().split("\n").filter(function (line) {
        return line.indexOf("/org/foamy/Plain ") === 0
      })
      test.check(JSON.stringify(plainLog) === JSON.stringify(["/org/foamy/Plain - secondary-activate"]), "right-click on it calls nothing on the app: " + JSON.stringify(plainLog))
      test.finish()
      break
    }
    if (!test.waiting && !test.finished)
      driver.restart()
  }
  function nextOrientation() {
    Commons.Color.shellValues = {}
    if (++orientation < positions.length) {
      configure("right", true)
      stage = 0
      return
    }
    orientation = 0
    configure("right", true)
    stage = 30
  }
  function finish() {
    finished = true
    console.log("FOAMY RESULT " + checks + " checks on 4.5")
    console.log("FOAMY DONE")
    Qt.quit()
  }
  Timer {
    interval: 80000
    running: true
    onTriggered: {
      console.log("FOAMY FAIL timeout at stage " + test.stage)
      Qt.exit(1)
    }
  }
}
