# Awesome desktop dotfiles

CachyOS/X11, floating AwesomeWM, four desktops, native panel and sidebar.
Frutiger Aero-inspired blue desktop chrome, Adwaita GTK controls/cursors, Breeze icons and VAX terminals.
Legacy configurations remain for reference; they are not the active session.

## Install

Required desktop packages (Breeze icons are provided by `breeze-icons`; Adwaita GTK controls and cursors are provided by the desktop GTK theme packages):

```sh
sudo pacman -S --needed stow awesome xsettingsd snixembed \
  xorg-xrandr xorg-xset xclip xdotool maim \
  xss-lock i3lock dunst dmenu pcmanfm \
  gtk2 gtk3 adwaita-icon-theme breeze-icons fontconfig dbus util-linux xdg-terminal-exec \
  kitty xfce4-appfinder lxqt-policykit wireplumber brightnessctl \
  playerctl pavucontrol picom python-gobject arandr
```

`xdg-terminal-exec` honors `~/.config/xdg-terminals.list`; this configuration
selects `kitty.desktop` for desktop applications marked `Terminal=true`.
The Start menu's **Control Panel** provides GTK appearance settings, display profiles,
ArandR, btop/htop, AMDGPU TOP, Task Manager, Bluetooth and power settings, plus audio/network launchers and a manual Solaar
launcher. `nm-connection-editor`, `amdgpu_top`, `htop`, `xfce4-taskmanager`,
`blueman-manager`, `xfce4-power-manager-settings`, and `solaar` remain optional;
Solaar is never started automatically. The Control Center's Sidebar tab controls
which sections appear; Quick Launch is hidden by default and can be enabled there.
Use **Save & Restart Awesome** or save and press Win+Ctrl+R. Trash and volume
remain in System Status. The sidebar News inbox is unread-first and starts with a
curated Wykop General RSS feed; configure any additional approved RSS/Atom sources
in `~/.config/awesome/news-feeds`.

From the repository root:

```sh
./stow.sh check                 # read-only preflight; also the default
./stow.sh apply                 # preflight, deploy links, refresh fonts
~/.local/bin/desktop-check      # read-only config/package health check
~/.local/bin/desktop-check --runtime  # also query the active X11 session
```

Existing files are never overwritten or adopted. Mutable MC/PCManFM state stays
local; see [deployment details](docs/desktop.md#install-and-deploy).
Helpers use `desktop-*` names. After Stow deployment, run `updaterepo` inside a
Git repository to fetch and fast-forward only when the worktree is clean; it also
initializes submodules and updates Git-Fat data when configured. Use
`./stow.sh unlink` to remove package-owned links.

## Validate

```sh
./tests/run.sh                  # syntax and unit tests
./tests/run.sh --session        # also test a private Awesome session
./tests/run.sh --visual         # also visual tests, without/with private Picom
```

See [test dependencies and details](tests/README.md).
Deployment and tests do not restart the live desktop.

## Session

Log out of the old WM before running `startx`. The real session uses the existing
systemd user D-Bus bus: **do not wrap Awesome in `dbus-run-session`**.
Clipboard history is off by default. To opt into clipmenu autostart when both
binaries are installed, run `DESKTOP_CLIPMENU_AUTOSTART=1 startx` (or export
that variable before starting Awesome). Manual launching remains available;
ordinary copy/paste and `xclip` screenshot copying are unaffected.

[Shortcuts, session details, troubleshooting](docs/desktop.md) ·
[Awesome components](dotfiles/.config/awesome/README.md)
