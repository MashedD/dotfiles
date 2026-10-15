# Desktop tests

From any directory, invoke the repository's runner:

```sh
./tests/run.sh             # syntax and unit tests (default)
./tests/run.sh --session   # also private Xvfb Awesome session
./tests/run.sh --visual    # also visual sessions without/with private Picom
```

The commands above assume the repository root; an absolute runner path also works.
The runner stops on failure; missing dependencies are errors, not skipped checks.
Sidebar edge-scroll tests wait for grab acquisition, drag feedback, scroll progress,
and bottom arrival before dropping. Failures report the stage, pointer/grab state,
viewport, scroll bounds and private log; stub tests verify failure cleanup without retries.
Fast checks need Bash, zsh (syntax-only), Awesome, Lua, and Python plus the helper-test dependencies
below. Deployment/runner tests use temporary homes and stub commands; real Stow
integration checks require GNU Stow. They also verify that the five local
MC/PCManFM state files survive apply/unlink without package copies or ignore rules.
Focused checks validate Code JSONC settings and the portable opencode PATH without
executing application or interactive shell startup. No tests change the live desktop.

## Awesome session

```sh
lua tests/test-awesome-appearance.lua
lua tests/test-awesome-data.lua
lua tests/test-awesome-interaction.lua
lua tests/test-awesome-calendar.lua
lua tests/test-awesome-launch.lua
python3 tests/test-awesome-session.py
python3 tests/test-awesome-session.py --composited
python3 tests/test-awesome-autostart.py
python3 tests/test-desktop-display.py
python3 tests/test-screen-lock.py
```

The Awesome runtime test uses a private Xvfb display and private D-Bus bus,
disables real autostart, and uses a temporary HOME/runtime directory. It
checks the native 30px panel/strut, date, volume controls (mocked audio commands),
Start menu, calendar, XEmbed tray ownership, wallpaper, plain corner resizing,
borderless maximization/fullscreen, floating clients/titlebars, four tags,
persistent sidebar fold/order and drag auto-scroll, send-and-follow, snapping,
show-desktop, close/reload, Win+P output menu, Win+Shift+Q confirmation/cancel,
and actual Win+L/i3lock. Lock readiness waits for a live process and visible window
on the private display; duplicate requests must retain the original locker root and
visible window IDs. Verified descendants of that root with the same executable are
allowed; independent roots, ambiguous ancestry and PID reuse fail. A focused Xvfb
diagnosis confirmed that this installed i3lock creates an internal i3lock child even
with `--nofork`; raw process counts therefore do not measure locker instances.
Failure output includes process ancestry/commands/executables and optional window PID
properties. Cleanup rechecks PID/start-time/display identities and waits for removal.
This checks window readiness, not authentication or input-grab security.
It also checks weather/crypto/quota stale-data retention and recovery, genuine zero
quota values, escaped reset text, and shared collectors when a second screen is
added and removed. All weather requests use a mocked curl; no network is needed.
The default cabin PNG is bundled and copied directly into the private home; a
missing default is a test failure, not silently substituted with another image.
Edge scrolling uses elapsed time at 180 px/s with a 250 ms catch-up cap; Lua tests
cover irregular timing, direction changes, inactive edges and lifecycle resets.

`test-desktop-check.py` uses isolated command/theme/font fixtures to verify quiet and
verbose output, warning/failure exits, validator diagnostics and read-only behavior.
`test-awesome-lock.py` uses fake process trees and time to cover internal children,
independent lockers, replaced roots/windows, ancestry errors and cleanup failures.

The Lua-only tests validate shared surface contrast over light/dark backgrounds,
trash semantic colors, response parsing, collector lifecycle, overlapping-request
prevention, command deadlines/spawn failures, stale aging, late results, release-to-activate
state transitions, executable lookup, spawn/notification failures, and calendar parsing. Contrast checks include the actual
sidebar window opacity as well as surface alpha.
Run them from the repository root with Lua 5.3 or later.

Requires Xvfb, awesome, awesome-client, xmessage, xdotool, xprop, i3lock, timeout and
dbus-run-session. To capture light/dark visual-review screenshots as well, install
ImageMagick and run:

```sh
AWESOME_TEST_SCREENSHOTS=/tmp/awesome-polish-shots python3 tests/test-awesome-session.py
AWESOME_TEST_VISUAL=1 python3 tests/test-awesome-session.py
```

`AWESOME_TEST_VISUAL=1` requires ImageMagick's `import` and `compare` commands. It
captures tight Start and workspace-button crops while normal, held, canceled, and
restored, then asserts pixel-level difference/restoration; missing tools are an explicit failure.
The same mode can be combined with `--composited`. Screenshots from
`AWESOME_TEST_SCREENSHOTS` include Start, display selection, window actions, quit confirmation,
Applications, the panel calendar, stale-data tooltips, and titlebar hover controls,
alongside the light/dark surface checks. The runtime test verifies menu palette
inheritance, tooltip colors/borders, release-to-activate sidebar buttons and menu items,
component teardown,
titlebar control geometry and hover restoration, and rejects Pango color errors.
`tests/helpers/awesome-ui.lua` contains private-session inspection helpers; it is loaded
and cached only in the isolated Awesome process, then naturally reloaded after a
complete process restart. `tests/helpers/awesome_controls.py` groups menu and workspace
pointer scenarios while receiving the session’s existing Lua, pointer, wait, and visual
helpers. The shared binding tests also cover moving, resizing, or hiding a control during
a grab, plus cancellation and ownership cleanup. Regression tests also cover native
grab startup/callback errors, external interruption, stale callbacks, and removal or
replacement of a held widget tree while its window remains visible. Sidebar values notify/render only on
visible changes; a shared clock tick remains independent of resource/system polling. Real pointer tests cover Start,
workspace selection, menu items, sidebar release-inside/release-outside, leave/re-enter,
right-click rejection, hidden decorations, client destruction during a press, delayed
tooltip visibility without focus changes, and removing a screen during a scrollbar drag
(including delayed-tooltip cancellation and idempotent teardown).

### Composited verification

`--composited` additionally requires Picom with an XRender backend. It launches Picom
on the private Xvfb display using the repository configuration and an XRender backend
override, waits for `_NET_WM_CM_S0` ownership, and terminates only that process at exit.
Missing Picom or backend startup failures are explicit test failures, not successful
or silently skipped composited checks. Production retains GLX; this test validates
alpha composition, not GPU driver performance. No live compositor is restarted.

```sh
AWESOME_TEST_SCREENSHOTS=/tmp/awesome-composited-shots python3 tests/test-awesome-session.py --composited
```

For extraction reviews, run the same command before/after into separate directories.
Compare geometry and visual states rather than exact hashes: clock hands, CPU/network
readings, timestamps, and client enumeration order naturally vary between sessions.

Only test-display i3lock processes are terminated afterward;
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
