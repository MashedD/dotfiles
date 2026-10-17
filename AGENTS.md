# AGENTS.md — dotfiles project

## Active desktop

- WM: **AwesomeWM** (X11), all normal/dialog windows floating by default
- Panel and systray: native Awesome wibar/widgets (30px top, Win98/Matrix), with snixembed as the StatusNotifierItem bridge
- Terminal: kitty
- Launcher: xfce4-appfinder
- File manager and desktop: pcmanfm
- Wallpaper: Awesome and the lock screen use the current selected wallpaper (default `aurora-cabin.png`, bundled cabin image).
- Notifications: dunst
- Do not start clipboard history by default. Users may opt into clipmenu autostart
  with `DESKTOP_CLIPMENU_AUTOSTART=1` when both binaries are installed; manual use
  remains available. Preserve ordinary copy/paste and `xclip` screenshot copying.
  Clipman’s XDG autostart is disabled for this profile, not manual launching.
- Authentication agent: lxqt-policykit
- Screen lock: xss-lock + i3lock (Win+L; locks after 10 minutes idle and before suspend)

## Awesome rules

- Configure the WM through `dotfiles/.config/awesome/rc.lua` and `autostart`.
- `startx` uses `dotfiles/.config/X11/xinitrc`, with `dotfiles/.xinitrc` as a forwarding entry point.
- Use floating by default; Win+Space toggles the current desktop between floating and tile layouts. The native panel is in `dotfiles/.config/awesome/panel.lua`; do not start LXPanel or another tray manager.
- Click-to-focus; keep square Win98 window geometry with restrained Frutiger Aero glass-gradient titlebars, clear text, teal/mint controls (always-on-top toggle, minimize, maximize), and a glossy red close button. The ↑ always-on-top button sits left of minimize and stays visibly pressed while enabled; it follows `client.ontop` without changing sticky/workspace state. Normal windows have a bottom-right left-drag resize grip; maximized/fullscreen windows have no borders or bottom strip. Fullscreen also hides the top titlebar and advertises zero X11 frame extents; maximized windows retain the 26px titlebar. Shared X11 helpers use the `desktop-*` prefix.
- Hide the panel and reserved sidebar only for fullscreen clients visible on the current workspace(s). A fullscreen client on another workspace must not hide desktop controls; restore them when switching away and preserve the client's fullscreen state.
- The session uses four desktops: **1**, **2**, **3**, and **4**.
  - Win+1–4 switches desktops.
  - Win+Shift+1–4 sends the focused window to a desktop and follows it.
  - Win+P opens the display-output menu centered on the focused screen.
  - Win+Shift+Q opens a centered quit confirmation.
- Start only X11-compatible services from Awesome autostart. Do not add Wayland daemons there.
- Autostart must tolerate Awesome reloads without duplicate services. Solaar is not started by default; users may still launch it manually. The sidebar reads Logitech mouse battery status directly from sysfs.
- Awesome's built-in systray is the sole XEmbed tray owner, displayed on the primary monitor. Start `snixembed --fork` after Awesome initializes it to bridge modern StatusNotifierItem applications (such as Gajim).
- Win+Shift+Q and Start-menu Logout quit Awesome; in a `startx` session this cleanly returns to the console.
- The `startx` session must use the existing systemd user D-Bus bus; do not wrap Awesome in `dbus-run-session`, which splits Gajim from GNOME Keyring.
- Private Xvfb tests may use an isolated D-Bus bus; never use it for the real desktop.
- The existing NetworkManager applet is started externally; do not start a second `nm-applet` from this configuration.
- Removable-drive handling is intentionally unchanged: do not add udiskie unless requested.

## Theme: Win98 + Matrix

Combine Windows 98 controls with Matrix-green accents.

- Awesome: square Win98 window geometry with Frutiger Aero glass-gradient titlebars and glossy controls; keep the rest of the desktop Win98/Matrix, with navy/slate sidebar surfaces and restrained VAX-green status accents. GTK theme: Adwaita with blue selection, Breeze icons, and Adwaita cursors; VAX palettes remain in terminals. Prefer Microsoft Sans Serif 8, with Liberation Sans fallback when unavailable.
- Awesome panel: top, 30px Frutiger Aero sky-blue/aqua glass surface with Start/application menu, workspace buttons, taskbar, tray, compact HH:MM clock, and Monday-first calendar popup. Keep the complete 65×25 Tux/Start asset at native size without extra label text, with its green glass face; anchor the Start menu flush left below it; a bare Win tap toggles the menu without interfering with Win shortcuts. Style all Awesome menus consistently with blue Longhorn glass gradients.
ld
- Right-edge sidebar starts in workarea-reserving mode so it stays visible and maximized windows leave room for it (hidden for fullscreen). Win+Shift+S cycles hidden → visible below windows → always on top → workarea-reserving → hidden. It spans workspaces; its reserved mode keeps windows left of it. Keep it flush beneath the panel with no outer padding or top/right/bottom border (retain the slim left accent); use blue headers over its dark navy/slate card surfaces; match the 26px main header height and Segoe UI title text to window titlebars. Include a centered date with a round, glassy blue analog clock (blue bezel, hour numerals, minute divisions, and hour/minute/second hands; clicking toggles to the blue digital date/time display and back), wallpaper picker, Bydgoszcz weather, a SYSTEM STATUS card for CPU, memory, laptop and Logitech mouse battery levels, network, root free space, and integrated volume control, plus Now Playing and a CRYPTO PRICES · USD card showing BTC, ETH, and LTC in the same formats as tmux `crypto-prices`, plus a CODEX section with remaining 5h/7d quotas, progress bars, reset times, and local dates/times for available free resets; center QUICK LAUNCH entries for Terminal, Files, Monitor, Finder, Quake 2 (`~/Games/quake2/q2pro.sh`) and Sleep (`systemctl suspend`), with a clickable empty/full Trash indicator opening `trash:///`. Show the first five top-level items from `~/Documents/todo.md` under `## Sidebar` (refresh every minute), and a CALENDAR card from `~/Documents/calendar.md` with one latest past event, today’s events, and the next three upcoming entries. Color dates and times separately; emphasize today and distinguish upcoming events. Keep the sidebar square-edged; the workarea-reserving state is the default. Clicking a section title folds it; dragging the title reorders sections, with order and collapsed state persisted together in `~/.local/state/awesome/sidebar-sections` (respect `$XDG_STATE_HOME`).
- Dunst: classic Win98 tooltip background `#ffffe1`, black text, square black border.
- Lock screen uses the current selected desktop wallpaper, without blur, animation, or transparency.
- Picom provides X11 compositing and opt-in transparency only: no fading, shadows, blur, inactive dimming, or rounded corners. Keep the AwesomeBar square, with a restrained forest-green left-to-right gradient and raised bevels.

## Directories

| Path | Purpose |
|------|---------|
| `dotfiles/.config/awesome/` | Active floating window-manager, keybinding, titlebar, menu and autostart configuration |
| `dotfiles/.config/picom/` | Active X11 compositor config; transparency support only, with visual effects disabled |
| `dotfiles/.config/X11/` | Active startx entry point and X resources |
| `dotfiles/.config/dunst/` | Active notification theme |
| `dotfiles/.local/bin/` | Active shared helpers (`desktop-*`) for volume, brightness, screenshots, locking, and battery alerts |
| `dotfiles/.local/share/icons/hicolor/32x32/apps/tux-start.png` | Stowed native-size Tux/Start button asset |
| `configs/` | Manual system-wide zsh environment reference (not Stowed) |

## Validation and reload

- Validate Awesome: `awesome -k -c ~/.config/awesome/rc.lua`
- Isolated runtime test: `python3 tests/test-awesome-session.py`
- Reload Awesome: `awesome-client 'awesome.restart()'`
- Lock-helper unit test: `python3 tests/test-screen-lock.py`
- Reload dunst: `dunstctl reload`
- A new login starts the autostart services; do not launch duplicate panel, notification, clipboard-manager, or lock daemons manually.
