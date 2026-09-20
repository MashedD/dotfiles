# Theme smoke test

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
