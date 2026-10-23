# Foamy Tray

Shows the whole active system tray in Omarchy Quattro, without a drawer or
pin/hide controls. App menus and nested submenus remain available.

Steam, Remmina, and ChatGPT use theme-aware icon glyphs and open their menus on
left-click. Cloudflare WARP also opens its menu on left-click. Other apps keep
their normal icons and click behavior. Right-click opens an app's menu.

Symbolic icons and WARP's monochrome icons follow the bar foreground in light
and dark themes. WARP retains its connection-state icon shapes and shows a
separate attention badge in the theme's urgent color for notifications. Popup
corners use twice Hyprland's `decoration:rounding` value; zero keeps them square.

## Install

```sh
omarchy plugin add https://github.com/foamrider/foamy-tray.git --enable
```

Remove your previous tray widget from the bar layout to avoid duplicate icons.
Supports horizontal and vertical bars. Apps marked passive do not appear.

On Omarchy 4.5, widgets in `bar.layout.tray` stay visible beside the application
icons, without a drawer. They remain visible even when no applications have tray
icons. Dragging a bar widget reveals a drop target when the section is empty.
Omarchy 4.0.6 continues to show application icons as before.

## Validate

Run `omarchy plugin validate .` and `./test.sh` in a graphical session. The test
opens a separate stock bar and uses a private D-Bus session with a synthetic app
icon; it does not change the installed layout or launch app actions. It requires
`python-dbus` and `python-gobject` for that fixture. Set `OMARCHY_PATH` to another
Omarchy source directory to test that version. Set `FOAMY_TRAY_CAPTURE_DIR` to an
existing directory to save horizontal and vertical, light and dark captures.

## Remove

```sh
omarchy plugin remove foamy.tray
```

Restore the stock tray through the bar settings if needed. Applications keep
running; removing this widget does not quit or uninstall them.

Omarchy manages the plugin entry in `shell.json`. Packages and data outside
the plugin directory are retained unless you remove them separately.

## License

Licensed under [MIT](LICENSE), with [Omarchy attribution](LICENSE-OMARCHY).
Provided **as is**, without warranty or guaranteed support. Use at your own risk.
