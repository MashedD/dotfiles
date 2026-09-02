# AGENTS.md — dotfiles project

## Active desktop

- WM: **Openbox** (X11)
- Panel and systray: lxpanel (VAX profile) with snixembed as the StatusNotifierItem bridge
- Terminal: kitty
- Launcher: xfce4-appfinder
- File manager and desktop: pcmanfm
- Wallpaper: pcmanfm (`win98-teal.svg`)
- Notifications: dunst
- Clipboard history: clipmenu (`clipmenud` service, Win+V)
- Authentication agent: lxqt-policykit
- Screen lock: xss-lock + i3lock (Win+L; locks after 10 minutes idle and before suspend)

Hyprland, Waybar, Walker, Mako, cliphist, and hyprlock configurations remain in the repository but are not part of the active Openbox session. `configs/dwm/` is legacy.

## Openbox rules

- Configure the session through `dotfiles/.config/openbox/rc.xml` and `autostart`.
- The session uses four desktops: **Main**, **Web**, **Chat**, and **Media**.
  - Win+1–4 switches desktops.
  - Win+Shift+1–4 sends the focused window to a desktop and follows it.
- Start only X11-compatible services from Openbox autostart. Do not add Wayland daemons there.
- LXPanel is the sole XEmbed tray owner. Start `snixembed --fork` after LXPanel only to bridge modern StatusNotifierItem applications (such as Gajim); do not add another panel or tray manager.
- LXPanel's Logout action runs `openbox --exit`; in a `startx` session this cleanly returns to the console.
- The existing NetworkManager applet is started externally; do not start a second `nm-applet` from this configuration.
- Removable-drive handling is intentionally unchanged: do not add udiskie unless requested.

## Theme: Win98 + Matrix

Combine Windows 98 controls with Matrix-green accents.

- Openbox theme: Chicago95. GTK theme: VAX (Chicago95 controls with Matrix-green selections), Microsoft Sans Serif 8.
- LXPanel: top, 30px Win98 panel; active elements use the dark-green `#001a00` / neon `#00ff41` pairing.
- Dunst: classic Win98 tooltip background `#ffffe1`, black text, square black border.
- Lock screen: Win98 teal with centered Tux, without blur, animation, or transparency.
- Keep effects minimal: no rounding, blur, or shadows that conflict with the pixel-era style.

## Directories

| Path | Purpose |
|------|---------|
| `dotfiles/.config/openbox/` | Active window-manager, keybinding, autostart, and Start-menu configuration |
| `dotfiles/.config/lxpanel/vax/` | Active panel, workspace pager, tray, battery, and status widgets |
| `dotfiles/.themes/VAX/` | Active GTK2 VAX overlay theme |
| `dotfiles/.config/dunst/` | Active notification theme |
| `dotfiles/.local/bin/` | Active Openbox helpers for volume, brightness, clipboard, locking, and battery alerts |
| `configs/` | Legacy configs, including dwm and st |
| `_old/` | Abandoned experiments |

## Validation and reload

- Reload Openbox: `openbox --reconfigure`
- Restart LXPanel: `lxpanelctl restart`
- Reload dunst: `dunstctl reload`
- A new login starts the autostart services; do not launch duplicate panel, notification, clipboard, or lock daemons manually.
