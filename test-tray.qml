import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "hostbar" as Host
import "plugin" as Foamy

ShellRoot {
  id: test
  property int checks: 0
  property int stage: 0
  property int orientation: 0
  property var positions: ["top", "left", "bottom", "right"]
  property var savedProbe: null
  property var savedTray: null
  readonly property bool rc: !!bar && "traySectionDragActive" in bar
  function check(ok, message) {
    if (!ok) { console.error("FAIL: " + message); Qt.exit(1); return }
    checks++
    console.log("PASS: " + positions[orientation] + ": " + message)
  }
  function configure(section, hasWidget, hasTray) {
    var layout = {left: [], center: [], right: [], tray: []}
    if (hasTray !== false) layout[section].push("foamy.tray")
    if (hasWidget) layout.tray = [{id: "test.widget", label: "Hosted widget", extent: 120}]
    bar.barConfig = {position: positions[orientation], background: "opaque", layout: layout}
  }
  function tray() { return bar.moduleWidgets("foamy.tray")[0] }
  function widget() { return bar.moduleWidgets("test.widget")[0] }
  function slotFor(id) {
    for (var i = 0; i < bar.moduleSlots.length; i++)
      if (bar.moduleSlots[i].activeItem && bar.moduleSlots[i].activeItem.moduleName === id) return bar.moduleSlots[i]
    return null
  }
  function capture(name) {
    var target = tray()
    var path = Quickshell.env("FOAMY_TRAY_CAPTURE_DIR")
    if (!target || !path) return
    target.grabToImage(function(result) { test.check(result.saveToFile(path + "/" + (test.rc ? "rc1-" : "406-") + name + ".png"), "tray capture saved") }, Qt.size(Math.max(1, target.width), Math.max(1,target.height)))
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
      function open() { opened = true }
      function close() { opened = false }
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
        Text { text: "Hosted panel"; color: Commons.Color.popups.text }
      }
    }
  }
  QtObject {
    id: registry
    property int revision: 0
    property var widgets: ({"foamy.tray": {component: trayComponent}, "test.widget": {component: widgetComponent}})
    function metadataFor(id) { return {firstParty: false} }
  }
  Loader {
    id: host
    source: Qt.resolvedUrl("hostbar/Bar.qml")
    onLoaded: {
      item.barWidgetRegistry = registry
      test.configure("right", true)
    }
  }
  readonly property var bar: host.item
  FileView { id: status; path: Quickshell.env("FOAMY_TRAY_TEST_STATUS") }
  Timer {
    interval: 350
    running: !!test.bar
    repeat: true
    onTriggered: {
      var t = test.tray()
      switch (test.stage++) {
      case 0:
        test.check(!!t, "real host loads the tray")
        test.check(t.trayItems.length === 0, "private bus starts without active app icons")
        if (!test.rc) {
          test.check(!t.visible && t.sectionExtent === 0, "old host leaves empty tray collapsed")
          status.setText("Active")
          test.stage = 15
          break
        }
        test.check(!!test.widget() && t.visible && t.sectionExtent === 120, "tray section renders with no app icons")
        test.check(test.widget().settings.label === "Hosted widget", "host injects section widget settings")
        test.check(t.sectionShown && t.sectionShown.width > 0 && t.sectionShown.height > 0, "section exposes visible geometry")
        test.savedProbe = test.widget()
        test.savedTray = t
        test.capture(test.positions[test.orientation] + "-dark-empty-apps")
        test.widget().open()
        break
      case 1:
        test.check(test.widget().opened && bar.traySectionPopoutOpen && t.visible, "hosted popup keeps its visible anchor")
        test.widget().close()
        status.setText("Active")
        break
      case 2:
        test.check(t.trayItems.length === 1 && t.visible, "active application icon joins hosted widget")
        test.check((t.vertical ? t.implicitHeight : t.implicitWidth) === 120 + t.trayItemExtent, "app and hosted sizes add without overlap")
        test.check(t.sectionHost.x === 0 && t.sectionHost.y === 0, "end-fixed tray keeps app at its fixed edge")
        test.capture(test.positions[test.orientation] + "-dark-app")
        test.configure("left", true)
        break
      case 3:
        test.check(t === test.savedTray && test.widget() === test.savedProbe, "moving tray preserves hosted widget instances")
        test.check(t.sectionEdge === "start", "start-fixed tray forwards its growth edge")
        test.check((t.vertical ? t.sectionHost.y : t.sectionHost.x) === t.trayItemExtent, "start-fixed tray puts section after app icons")
        Commons.Color.shellValues = {"bar.background":"#fafafa", "bar.text":"#202020", "popups.background":"#fafafa", "popups.text":"#202020", "popups.border":"#404040"}
        break
      case 4:
        test.capture(test.positions[test.orientation] + "-light-app")
        test.configure("left", false)
        break
      case 5:
        test.check(t.sectionExtent === 0 && t.trayItems.length === 1 && t.visible, "removing hosted widgets leaves app icons")
        status.setText("Passive")
        break
      case 6:
        test.check(!t.visible && t.sectionExtent === 0, "empty tray takes no space outside a drag")
        // Exercise the actual bar's geometry and drop-target code without persisting a move.
        bar.barConfig = {position: test.positions[test.orientation], background: "opaque",
          layout: {left:["foamy.tray"], center:[], right:[{id:"test.widget", extent:80}], tray:[]}}
        test.stage = 18
        break
      case 7:
        test.check(t.visible && t.sectionExtent >= t.trayItemExtent, "drag exposes empty section drop target")
        var slot = test.slotFor("foamy.tray")
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
        Commons.Color.shellValues = {}
        if (++test.orientation < test.positions.length) {
          test.configure("right", true)
          test.stage = 0
          break
        }
        test.finish()
        break
      case 18:
        bar.beginBarDrag(test.slotFor("test.widget"), 5, 5)
        test.stage = 7
        break
      case 15:
        test.check(t.trayItems.length === 1 && t.visible && t.sectionExtent === 0, "old host shows ordinary app icon")
        test.check((t.vertical ? t.implicitHeight : t.implicitWidth) === t.trayItemExtent, "old host keeps app icon dimensions")
        test.capture(test.positions[test.orientation] + "-dark-app")
        Commons.Color.shellValues = {"bar.background":"#fafafa", "bar.text":"#202020", "popups.background":"#fafafa", "popups.text":"#202020", "popups.border":"#404040"}
        break
      case 16:
        test.capture(test.positions[test.orientation] + "-light-app")
        status.setText("Passive")
        break
      case 17:
        test.check(!t.visible, "passive icon is excluded")
        Commons.Color.shellValues = {}
        if (++test.orientation < test.positions.length) {
          test.configure("right", true)
          test.stage = 0
          break
        }
        test.finish()
      }
    }
  }
  function finish() { console.log("RESULT: " + checks + " tray integration checks passed"); Qt.quit() }
  Timer { interval: 30000; running: true; onTriggered: { console.error("FAIL: timeout"); Qt.exit(1) } }
}
