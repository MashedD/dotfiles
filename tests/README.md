# Desktop tests

## Awesome session

```sh
python3 tests/test-awesome-session.py
python3 tests/test-awesome-autostart.py
python3 tests/test-openbox-display.py
python3 tests/test-screen-lock.py
```

The Awesome runtime test uses a private Xvfb display and private D-Bus bus,
disables real autostart, and uses a temporary HOME/runtime directory. It
checks the native 30px panel/strut, date, volume controls (mocked audio commands),
Start menu, calendar, XEmbed tray ownership, wallpaper, plain corner resizing,
borderless maximization/fullscreen, floating clients/titlebars, four tags, send-and-follow,
snapping, show-desktop, close/reload, Win+P output menu, Win+Shift+Q confirmation/cancel,
and actual Win+L/i3lock.
Requires Xvfb, awesome, awesome-client, xmessage, xdotool, xprop, i3lock and
dbus-run-session. Only test-display i3lock processes are terminated afterward;
the live WM/display and lock are never modified.

The mocked autostart test checks duplicate prevention on reload, tray startup
delay, no LXPanel, Solaar, or Clipman startup, and clipmenu-only history
without launching real services. Display profile tests mock all RandR
calls and assert internal-only, HDMI-only, and extended layouts. The display-helper test mocks RandR and does not change hardware modes.
The lock-helper test checks foreground waiting, image cleanup, conversion-failure
fallback, inherited suspend FD and duplicate prevention using a mock locker.

## Theme smoke test

`icon-probe.c` verifies that the named `vax-tux-start` icon resolves through
the active GTK icon theme. Run it after `setup-vax-theme` has generated VAX at
`$XDG_DATA_HOME/themes/VAX` (or the default `~/.local/share/themes/VAX`):

```sh
probe_dir=$(mktemp -d /tmp/vax-icon-probe.XXXXXX)
gcc -Wall -Wextra tests/icon-probe.c \
  $(pkg-config --cflags --libs gtk+-2.0) -o "$probe_dir/gtk2-probe"
gcc -Wall -Wextra tests/icon-probe.c \
  $(pkg-config --cflags --libs gtk+-3.0) -o "$probe_dir/gtk3-probe"

GTK2_RC_FILES="${XDG_DATA_HOME:-$HOME/.local/share}/themes/VAX/gtk-2.0/gtkrc" \
XDG_DATA_DIRS="${XDG_DATA_HOME:-$HOME/.local/share}:/usr/local/share:/usr/share" \
  timeout 5s xvfb-run -a "$probe_dir/gtk2-probe"
XDG_DATA_DIRS="${XDG_DATA_HOME:-$HOME/.local/share}:/usr/local/share:/usr/share" \
  timeout 5s xvfb-run -a "$probe_dir/gtk3-probe"
```

Both commands should print the generated
`icons/hicolor/32x32/apps/vax-tux-start.png` path.
