# Awesome desktop dotfiles

CachyOS/X11, floating AwesomeWM, four desktops, native panel and sidebar.
Win98/Matrix styling with Frutiger Aero glass titlebars.
Legacy configurations remain for reference; they are not the active session.

## Install

Required desktop packages (Chicago95 must be installed separately):

```sh
sudo pacman -S --needed stow awesome xsettingsd snixembed \
  xorg-xrandr xorg-xset xclip xdotool maim \
  xss-lock i3lock dunst clipmenu dmenu pcmanfm \
  gtk2 gtk3 fontconfig dbus util-linux xdg-terminal-exec \
  kitty xfce4-appfinder lxqt-policykit wireplumber brightnessctl \
  playerctl pavucontrol picom
```

`xdg-terminal-exec` honors `~/.config/xdg-terminals.list`; this configuration
selects `kitty.desktop` for desktop applications marked `Terminal=true`.

From the repository root:

```sh
./stow.sh check                 # read-only preflight; also the default
./stow.sh apply                 # preflight, deploy links, refresh fonts
./setup-vax-theme               # generate VAX from installed Chicago95
~/.local/bin/desktop-check      # read-only desktop health check
```

Existing files are never overwritten or adopted. Mutable MC/PCManFM state stays
local; see [deployment details](docs/desktop.md#install-and-deploy).
Helpers use `desktop-*` names. Use `./stow.sh unlink` to remove package-owned links.

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
Do not manually start duplicate panel, notification, clipboard, or lock services.

[Shortcuts, session details, troubleshooting](docs/desktop.md) ·
[Awesome components](dotfiles/.config/awesome/README.md)
