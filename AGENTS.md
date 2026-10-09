# AGENTS.md — dotfiles project

## Active desktop

- WM: **AwesomeWM** (X11), all normal/dialog windows floating by default
- Panel and systray: native Awesome wibar/widgets (30px top, Win98/Matrix), with snixembed as the StatusNotifierItem bridge
- Terminal: kitty
- Launcher: xfce4-appfinder
- File manager and desktop: pcmanfm
- Wallpaper: Awesome and the lock screen use the current selected wallpaper (default `aurora-longhorn.png`, abstract Aurora; no logo).
- Notifications: dunst
- Clipboard history: clipmenu only when installed; Win+V. Clipman is explicitly disabled; do not add it as a fallback.
- Authentication agent: lxqt-policykit
- Screen lock: xss-lock + i3lock (Win+L; locks after 10 minutes idle and before suspend)

Openbox, Hyprland, Waybar, Walker, Mako, cliphist, and hyprlock configurations remain in the repository but are not part of the active Awesome session. `configs/dwm/` is legacy.

## Awesome rules

- Configure the WM through `dotfiles/.config/awesome/rc.lua` and `autostart`.
- `startx` uses `dotfiles/.config/X11/xinitrc`, with `dotfiles/.xinitrc` as a forwarding entry point.
- Keep only the floating layout. The native panel is in `dotfiles/.config/awesome/panel.lua`; do not start LXPanel or another tray manager.
- Click-to-focus; square Win98/Matrix titlebars. Normal windows have a bottom-right left-drag resize grip; maximized/fullscreen windows have no borders or bottom strip. Retain `openbox-*` helpers for compatibility.
- The session uses four desktops: **1**, **2**, **3**, and **4**.
  - Win+1–4 switches desktops.
  - Win+Shift+1–4 sends the focused window to a desktop and follows it.
  - Win+P opens display outputs; Win+Shift+Q requires quit confirmation.
- Start only X11-compatible services from Awesome autostart. Do not add Wayland daemons there.
- Autostart must tolerate Awesome reloads without duplicate services. Start Solaar with `--window=hide` after the SNI bridge when installed.
- Awesome's built-in systray is the sole XEmbed tray owner, displayed on the primary monitor. Start `snixembed --fork` after Awesome initializes it to bridge modern StatusNotifierItem applications (such as Gajim).
- Win+Shift+Q and Start-menu Logout quit Awesome; in a `startx` session this cleanly returns to the console.
- The `startx` session must use the existing systemd user D-Bus bus; do not wrap Awesome in `dbus-run-session`, which splits Gajim from GNOME Keyring.
- Private Xvfb tests may use an isolated D-Bus bus; never use it for the real desktop.
- The existing NetworkManager applet is started externally; do not start a second `nm-applet` from this configuration.
- Removable-drive handling is intentionally unchanged: do not add udiskie unless requested.

## Theme: Win98 + Matrix

Combine Windows 98 controls with Matrix-green accents.

- Awesome: square Win98 titlebars, Matrix-green active titles, Microsoft Sans Serif 8. GTK theme: VAX (Chicago95 controls with Matrix-green selections). Prefer Microsoft Sans Serif 8, with Liberation Sans fallback when unavailable.
- Awesome panel: top, 30px Win98 panel, Start/application menu, workspace buttons, taskbar, tray, compact HH:MM clock, and Monday-first calendar popup. Render the complete 65×25 Start asset at native size without extra label text. Active elements use the dark-green `#001a00` / neon `#00ff41` pairing.
- Optional right-edge sidebar toggled with Win+Shift+S: flush to screen edges beneath the panel, no outer padding or top/right/bottom borders (retain a slim left accent). Include the centered date/time, wallpaper preview picker (click to apply; previous/next to browse, selection persists), Bydgoszcz weather, CPU, memory, battery, network, free space on `/`, volume, Now Playing, and centered quick launch. Keep hidden by default and non-reserving.
- Dunst: classic Win98 tooltip background `#ffffe1`, black text, square black border.
- Lock screen: Win98 teal with centered Tux, without blur, animation, or transparency.
- Picom provides X11 compositing and opt-in transparency only: no fading, shadows, blur, inactive dimming, or rounded corners. Keep the AwesomeBar square, with a restrained forest-green left-to-right gradient and raised bevels.

## Directories

| Path | Purpose |
|------|---------|
| `dotfiles/.config/awesome/` | Active floating window-manager, keybinding, titlebar, menu and autostart configuration |
| `dotfiles/.config/picom/` | Active X11 compositor config; transparency support only, with visual effects disabled |
| `dotfiles/.config/X11/` | Active startx entry point and X resources |
| `dotfiles/.config/openbox/` | Previous window-manager configuration, retained for reference |
| `dotfiles/.config/lxpanel/vax/` | Previous panel configuration, retained for reference |
| `themes/VAX/` | VAX source templates; generated output is installed separately by `setup-vax-theme` |
| `dotfiles/.config/dunst/` | Active notification theme |
| `dotfiles/.local/bin/` | Active shared helpers (openbox-* names retained) for volume, brightness, clipboard, locking, and battery alerts |
| `configs/` | Legacy configs, including dwm and st |
| `_old/` | Abandoned experiments |

## Validation and reload

- Validate Awesome: `awesome -k -c ~/.config/awesome/rc.lua`
- Isolated runtime test: `python3 tests/test-awesome-session.py`
- Reload Awesome: `awesome-client 'awesome.restart()'`
- Lock-helper unit test: `python3 tests/test-screen-lock.py`
- Reload dunst: `dunstctl reload`
- A new login starts the autostart services; do not launch duplicate panel, notification, clipboard, or lock daemons manually.
