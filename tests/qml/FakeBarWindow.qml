import QtQuick
import Quickshell

// Offscreen stand-in for the PanelWindow the host Bar.qml is built on
// (offscreen Qt has no layer shell). tests/runtime.py loads the host's real
// Bar.qml with `PanelWindow` swapped for this, `anchors { … }` turned into
// `windowAnchors { … }`, the window's implicit size into `requested…`, and
// the WlrLayershell lines dropped. Everything else is the host's own code.
// Like a layer surface, a window anchored to two opposite edges spans them.
FloatingWindow {
  id: window
  property int exclusionMode: 0
  property int exclusiveZone: 0
  property real requestedWidth: 0
  property real requestedHeight: 0
  readonly property FakeBarEdges margins: FakeBarEdges {}
  readonly property FakeBarEdges windowAnchors: FakeBarEdges {}

  implicitWidth: windowAnchors.left && windowAnchors.right && screen ? screen.width : Math.max(1, requestedWidth)
  implicitHeight: windowAnchors.top && windowAnchors.bottom && screen ? screen.height : Math.max(1, requestedHeight)
}
