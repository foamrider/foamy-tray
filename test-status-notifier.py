"""Private-session status notifier fixture; never connects to the desktop bus."""
import sys
from pathlib import Path
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName('org.foamy.TrayTest', bus=bus)
interface = 'org.kde.StatusNotifierItem'
status_file = Path(sys.argv[1])

class Item(dbus.service.Object):
    status = 'Passive'
    registered = False

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, requested):
        return {'Category': 'ApplicationStatus', 'Id': 'foamy-test', 'Title': 'Test app',
                'Status': self.status, 'IconName': '', 'IconPixmap': dbus.Array([(16,16,dbus.ByteArray(bytes([255,125,90,210])*256))], signature='(iiay)'), 'ItemIsMenu': False,
                'Menu': dbus.ObjectPath('/NO_DBUSMENU')}

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, requested, key):
        return self.GetAll(requested)[key]

    @dbus.service.signal(interface, signature='s')
    def NewStatus(self, status):
        pass

    def poll(self):
        if not self.registered:
            try:
                watcher = bus.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher')
                watcher.RegisterStatusNotifierItem('org.foamy.TrayTest', dbus_interface='org.kde.StatusNotifierWatcher')
                self.registered = True
            except dbus.DBusException:
                return True
        status = status_file.read_text().strip()
        if status != self.status:
            self.status = status
            self.NewStatus(status)
        return True

item = Item(bus, '/StatusNotifierItem')
GLib.timeout_add(50, item.poll)
GLib.MainLoop().run()
