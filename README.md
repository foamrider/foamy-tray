# Foamy Tray

Shows the whole active system tray in Omarchy Quattro, without a drawer or
pin/hide controls. App menus and nested submenus remain available.

Steam, Remmina, and ChatGPT use theme-aware icon glyphs and open their menus on
left-click. Cloudflare WARP also opens its menu on left-click. Other apps keep
their normal icons and click behavior. Right-click opens an app's menu.

## Install

```sh
omarchy plugin add https://github.com/foamrider/foamy-tray.git --enable
```

Remove your previous tray widget from the bar layout to avoid duplicate icons.
Supports horizontal and vertical bars. Apps marked passive do not appear.

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
