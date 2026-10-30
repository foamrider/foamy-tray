"""Two synthetic tray apps with DBusMenus, for tests/runtime.py.

Runs only on the private bus that tests/runtime.py starts with
dbus-run-session; it refuses to start on any other bus.

  status_notifier.py <status-file> <events-file>

Line 1 of the status file is the first app's status (Passive/Active/
NeedsAttention), line 2 the second app's (Passive when missing). Menu clicks
are appended to the events file as "<item path> <menu id> <event>".
"""
import os
import sys
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

if os.environ.get("FOAMY_TRAY_PRIVATE_BUS") != os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
    sys.exit("status_notifier.py: refusing to run outside the test's private bus")

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
status_file = Path(sys.argv[1])
events_file = Path(sys.argv[2])
SNI = "org.kde.StatusNotifierItem"
MENU = "com.canonical.dbusmenu"
PROPS = "org.freedesktop.DBus.Properties"
PIXMAP = dbus.Array([(16, 16, dbus.ByteArray(bytes([255, 125, 90, 210]) * 256))], signature="(iiay)")


class Menu(dbus.service.Object):
    """A minimal com.canonical.dbusmenu server over a static tree."""

    def __init__(self, path, owner, tree):
        super().__init__(bus, path)
        self.owner = owner
        self.items = {}
        self.children = {}
        self._index(0, {"children-display": "submenu"}, tree)

    def _index(self, item_id, props, children):
        self.items[item_id] = props
        self.children[item_id] = [child[0] for child in children]
        for child_id, child_props, grandchildren in children:
            if grandchildren:
                child_props = dict(child_props, **{"children-display": "submenu"})
            self._index(child_id, child_props, grandchildren)

    def _props(self, item_id, names):
        props = self.items.get(item_id, {})
        if names:
            props = {key: value for key, value in props.items() if key in names}
        return dbus.Dictionary(props, signature="sv")

    def _layout(self, item_id, depth, names):
        children = []
        if depth != 0:
            for child in self.children.get(item_id, []):
                children.append(dbus.Struct(self._layout(child, depth - 1, names), signature="ia{sv}av", variant_level=1))
        return (dbus.Int32(item_id), self._props(item_id, names), dbus.Array(children, signature="v"))

    @dbus.service.method(MENU, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent, depth, names):
        return dbus.UInt32(1), dbus.Struct(self._layout(parent, depth, names), signature="ia{sv}av")

    @dbus.service.method(MENU, in_signature="aias", out_signature="a(ia{sv})")
    def GetGroupProperties(self, ids, names):
        ids = ids or list(self.items)
        return dbus.Array([dbus.Struct((dbus.Int32(i), self._props(i, names)), signature="ia{sv}") for i in ids if i in self.items],
                          signature="(ia{sv})")

    @dbus.service.method(MENU, in_signature="is", out_signature="v")
    def GetProperty(self, item_id, name):
        return self.items[item_id][name]

    @dbus.service.method(MENU, in_signature="isvu", out_signature="")
    def Event(self, item_id, event, data, timestamp):
        with events_file.open("a") as out:
            out.write(f"{self.owner} {item_id} {event}\n")

    @dbus.service.method(MENU, in_signature="a(isvu)", out_signature="ai")
    def EventGroup(self, events):
        for item_id, event, data, timestamp in events:
            self.Event(item_id, event, data, timestamp)
        return dbus.Array([], signature="i")

    @dbus.service.method(MENU, in_signature="i", out_signature="b")
    def AboutToShow(self, item_id):
        return False

    @dbus.service.method(MENU, in_signature="ai", out_signature="aiai")
    def AboutToShowGroup(self, ids):
        return dbus.Array([], signature="i"), dbus.Array([], signature="i")

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {"Version": dbus.UInt32(3), "TextDirection": "ltr", "Status": "normal",
                "IconThemePath": dbus.Array([], signature="s")}

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, key):
        return self.GetAll(interface)[key]

    @dbus.service.signal(MENU, signature="ui")
    def LayoutUpdated(self, revision, parent):
        pass


class Item(dbus.service.Object):
    def __init__(self, path, item_id, title, line, menu_path):
        super().__init__(bus, path)
        self.path = path
        self.item_id = item_id
        self.title = title
        self.line = line
        self.menu_path = menu_path
        self.status = "Passive"
        self.registered = False

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return {"Category": "ApplicationStatus", "Id": self.item_id, "Title": self.title,
                "Status": self.status, "IconName": "", "IconPixmap": PIXMAP, "ItemIsMenu": False,
                "Menu": dbus.ObjectPath(self.menu_path)}

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, key):
        return self.GetAll(interface)[key]

    @dbus.service.method(SNI, in_signature="ii", out_signature="")
    def Activate(self, x, y):
        with events_file.open("a") as out:
            out.write(f"{self.path} - activate\n")

    @dbus.service.signal(SNI, signature="s")
    def NewStatus(self, status):
        pass

    def poll(self):
        if not self.registered:
            try:
                watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
                watcher.RegisterStatusNotifierItem(self.path, dbus_interface="org.kde.StatusNotifierWatcher")
                self.registered = True
            except dbus.DBusException:
                return True
        lines = status_file.read_text().split("\n") if status_file.exists() else []
        status = (lines[self.line].strip() if len(lines) > self.line else "") or "Passive"
        if status != self.status:
            self.status = status
            self.NewStatus(status)
        return True


first_menu = Menu("/org/foamy/One/Menu", "/org/foamy/One", [
    (1, {"label": "Open window"}, []),
    (2, {"type": "separator"}, []),
    (3, {"label": "Stations"}, [
        (31, {"label": "Radio A", "toggle-type": "radio", "toggle-state": 0}, []),
        (32, {"label": "Radio B", "toggle-type": "radio", "toggle-state": 1}, []),
    ]),
    (4, {"label": "Offline mode", "enabled": False}, []),
    (5, {"label": "Quit"}, []),
])
second_menu = Menu("/org/foamy/Two/Menu", "/org/foamy/Two", [
    (1, {"label": "Second action"}, []),
])
items = [Item("/org/foamy/One", "foamy-test", "Test app", 0, "/org/foamy/One/Menu"),
         Item("/org/foamy/Two", "foamy-second", "Second app", 1, "/org/foamy/Two/Menu")]
for item in items:
    GLib.timeout_add(50, item.poll)
GLib.MainLoop().run()
