# Desktop tests

Opt-in idle audit (about 13 minutes; passive live sampling, then private fixtures):
`python3 tests/audit-awesome-idle.py`. See [measurements and limitations](../docs/idle-performance.md).
Opt-in private rendering comparison: `python3 tests/audit-awesome-idle.py --rendering --output /tmp/awesome-render-audit.json`
(A–B–B–A, about 16 minutes; no live sampling). [Results and cache rejection](../docs/idle-performance.md#rendering-follow-up-cache-evaluated-not-shipped).
Opt-in per-widget rendering breakdown: `python3 tests/audit-awesome-idle.py --render-breakdown --output /tmp/awesome-render-breakdown.json`
(about 10 minutes; private Xvfb/D-Bus only, no live sampling). [Method and findings](../docs/idle-performance.md#per-widget-rendering-breakdown).

Opt-in semantic sidebar text attribution: `python3 tests/audit-awesome-idle.py --render-attribution --output /tmp/awesome-sidebar-attribution.json`
(about 10 minutes; private Xvfb/D-Bus only, no live sampling or text/markup capture). [Method and findings](../docs/idle-performance.md#semantic-sidebar-text-attribution).
Focused read-only stats probe: `lua5.3 tests/probe-awesome-stats.lua` (60 samples,
requires lgi for that Lua version); [results and usage](../docs/idle-performance.md#follow-up-exact-statistics-io-2026-10-15).

From any directory, invoke the repository's runner:

```sh
./tests/run.sh             # syntax and unit tests (default)
./tests/run.sh --session   # also private Xvfb Awesome session
./tests/run.sh --visual    # also visual sessions without/with private Picom
./tests/run.sh --session --scenario titlebars   # fast checks + focused runtime
./tests/run.sh --session --scenario menu-popups # verify popup placement and Start menu entries
./tests/run.sh --session --scenario sidebar-news # offline RSS inbox/popup interactions
./tests/run.sh --visual --scenario titlebars    # fast checks + focused visual matrix
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
python3 tests/test-control-center.py  # settings I/O only; no service restarts
python3 tests/test-awesome-autostart.py
python3 tests/test-desktop-display.py
python3 tests/test-screen-lock.py
```

### Focused runtime scenarios

```sh
python3 tests/test-awesome-session.py --scenario titlebars
python3 tests/test-awesome-session.py --scenario workspace-transfer
python3 tests/test-awesome-session.py --scenario sidebar-documents
python3 tests/test-awesome-session.py --scenario sidebar-settings
python3 tests/test-awesome-session.py --scenario sidebar-news
python3 tests/test-awesome-session.py --scenario sidebar-personalization
python3 tests/test-awesome-session.py --scenario sidebar-quick-launch-empty
python3 tests/test-awesome-session.py --scenario menu-popups
AWESOME_TEST_VISUAL=1 python3 tests/test-awesome-session.py --scenario titlebars
AWESOME_TEST_VISUAL=1 python3 tests/test-awesome-session.py --scenario titlebars --composited
```

The direct Python command skips the fast suite. `all` is the default;
`titlebars`, `workspace-transfer`, `sidebar-documents`, `sidebar-settings`,
`sidebar-news`, `sidebar-personalization`, `sidebar-quick-launch-empty`, and
`menu-popups` are focused alternatives, with one selector per invocation.
`./tests/run.sh --session` runs the workspace-transfer, sidebar-document,
sidebar-settings, offline news, personalization, and empty-launcher scenarios
separately, then the broad session. `--scenario` selects
one scenario instead.
`--help` describes the flags. Invalid arguments fail before launching the private bus
or display; the shell selector requires `--session` or `--visual`.

Titlebars initialize their own desktop/layout/sidebar baseline and normal fixture
windows, then run control/tooltip/always-on-top checks, maximized drag-to-restore,
click/double-click preservation, top/left/right edge snapping (including top-corner
priority), narrow normal/dialog titlebars, window-menu, Close, and unmanage/cancellation
checks used by the full suite.
The workspace-transfer scenario exercises cancellation on release outside and a
real move to the hovered workspace; failures include the drag stage, target, client/tag,
grab, button, pointer, and Awesome log. Sidebar-document checks click actual TODO and
calendar rows and report the click target, current widget counts, launcher actions, and
Awesome log. The sidebar-news scenario uses a local stateful feed stub to exercise
its unread/category filters, popup placement, wheel scrolling, Firefox mark-read behavior,
mark-unread, Mark all read, removal, Escape, and outside-click dismissal; it needs no
network. These focused paths avoid running the long unrelated integration sequence.

Titlebars do not run sidebar interactions, workspaces, persistence/reload, broad fullscreen
restoration, screen removal, or locking. Brief fullscreen interruptions of titlebar
presses remain included. Shared fixture files, mocked collectors, startup/shutdown
checks, optional screenshots, and private process cleanup remain unchanged.
`helpers/awesome_titlebars.py` holds the extracted checks; full runs retain their
original order, including the late destruction checks. `test-awesome-titlebar-drag.lua` covers pointer-anchor math, drag threshold, edge
priority and tiled/fullscreen guards without X11. The titlebar-drag work adds no
production settings or runtime dependencies.

Runs print executed titlebar groups and monotonic elapsed times; focused success is
explicitly labeled, never reported as complete-suite success. In one sequential local
verification matrix, private-session times were 29–30 seconds focused versus 79–81
seconds complete (normal, visual, and XRender-composited). These exclude the shell
runner's fast checks and are observations, not a portable timing guarantee or a
production desktop performance improvement. Argument/dispatch and runner failure
paths are tested without X11 by `test-awesome-session-runner.py` and
`test-deployment.py`.

### Complete session coverage

The Awesome runtime test uses a private Xvfb display and private D-Bus bus,
disables real autostart, and uses a temporary HOME/runtime directory. It
checks the native 30px panel/strut, date, volume controls (mocked audio commands),
Start menu (unique underlined mnemonics, immediate key activation, and existing
keyboard/mouse behavior), calendar, XEmbed tray ownership, wallpaper, plain corner
resizing,
borderless maximization/fullscreen, zero fullscreen `_NET_FRAME_EXTENTS` and
screen-sized native client bounds (not just WM outer geometry), repeated floating
fullscreen round trips without size drift, complete maximize → fullscreen → exit →
unmaximize restoration (including original border/geometry), axis-only maximization,
real fullscreen EWMH requests, rapid transitions, pending-refit destruction and
cross-monitor workarea fitting,
workspace-aware panel/sidebar restoration
(including repeated switches, client retagging, sticky/hidden/minimized states),
floating clients/titlebars, four tags,
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
It also checks weather/crypto stale-data retention, fail-closed quota display and
recovery (including cached source age and legacy stale markers), genuine zero
quota values, escaped reset text, and shared collectors when a second screen is
added and removed. All weather requests use a mocked curl; no network is needed.
The default cabin PNG is bundled and copied directly into the private home; a
missing default is a test failure, not silently substituted with another image.
Edge scrolling uses elapsed time at 180 px/s with a 250 ms catch-up cap; Lua tests
cover irregular timing, direction changes, inactive edges and lifecycle resets.

`test-status-helpers.py` runs the actual Codex/crypto shell helpers with isolated
caches and fake backends, never a real account or network. It covers legacy orphan
lock directories, advisory-lock contention and SIGKILL recovery, original cache
age, malformed/partial quota responses, true zero and conservative fractional
percentages, future timestamps, bounded Codex transport fallback and process-group
cleanup, and the actual helper-to-Lua-parser wire format.
Native quota tests assert that errors/stale data hide every percentage/bar, tooltips
retain source-confirmation time and failure reasons, and alternating plain-text/markup
updates cannot leave cached old label content.

`test-desktop-check.py` uses isolated command/theme/font/process fixtures to verify quiet
and verbose output, static and runtime checks, no-display skipping, required/optional
service failures, validator diagnostics and read-only behavior. `test-updaterepo.py`
stubs Git to check clean-tree fast-forward ordering, recursive submodule/Git-Fat updates,
and skipping the pull when local changes are present.
`test-awesome-fullscreen.lua` checks geometry delegation, independent restore state,
missing state, reentrancy/error cleanup, refit coalescing and installation with fake
clients. The private restore tests assert native results before fixture cleanup;
they do not repair geometry or borders to obtain a passing restoration assertion.
The native paired-axis EWMH removal limitation and native fullscreen `ontop` reset
are left unchanged; removal uses the regular WM API after testing EWMH entry.
`test-awesome-battery.lua` covers async laptop reads, aggregation, failures, zero
values, cancellation and late callbacks with fake I/O; shared-collector tests verify
pending/stale behavior and final-subscriber cancellation. No real battery reads run
in the fast tests.
`test-awesome-lock.py` uses fake process trees and time to cover internal children,
independent lockers, replaced roots/windows, ancestry errors and cleanup failures.

`test-desktop-news.py` uses offline RSS/Atom fixtures to cover HTML sanitization,
URL safety, bounded parsing, configurable category/feed validation, one-time legacy
migration, empty first-run configuration, read-state retention, feed failures,
inbox-capacity eviction, concurrent state writes, and dismissal tombstones. The
public Wykop endpoint was checked separately with a bounded request; live network
checks are not part of the deterministic test suite.

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
titlebar control geometry and hover restoration, normal/dialog titlebars at 16–400px
widths (including all responsive breakpoints), Close hit targets, Alt+Space fallback,
narrow title dragging/double-clicking, omitted-control press/tooltip cancellation,
and exact wide-titlebar pixel comparison against the historical layout. It also
checks always-on-top release/cancellation and external state synchronization
(including hidden/destroyed controls), and rejects Pango color errors.
The full session also runs `helpers/awesome_keyboard.py`: modal Win+S navigation,
calendar day/week/month selection, section folding, volume/mixer/document actions,
ignored application input, Lock/NumLock handling, direct WM-shortcut dispatch,
Escape/Win-tap/menu handoffs, temporary raising without changed struts, mouse
handoff, competing grabs, fullscreen and multi-screen teardown. External launch,
suspend and lock commands are stubbed for this audit, then restored before the
existing private real-lock checks. Visual runs compare an active focus outline and
exactly restored inactive header pixels. `test-awesome-keyboard.lua` covers the
controller, callback registry and local-noon calendar arithmetic without X11;
run it with `TZ=Europe/Warsaw` too to exercise DST boundaries.
`helpers/awesome_calendar.py` checks rollover on the real private calendar with
scoped fake dates: same-day browsing, midnight/month/year/leap-day transitions,
multi-day resume and backward dates, displayed today's events, active-grid
reattachment/visibility, and unchanged hidden/folded state. Its private refresh timer
is paused only for the fake-clock fixture and restored afterward, as are documents,
calendar state and `os.date` (including an injected error path). No system time is
changed. The simple reorder
drag now waits for acquisition and threshold feedback, with unit failure-path
checks; final ordering assertions and existing timeouts are unchanged.

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
delay, default-off clipboard history, clipmenu opt-in startup, and that LXPanel,
Solaar, and Clipman are not started by this profile, without launching real
services. Display profile tests mock all RandR calls and assert internal-only,
HDMI-only, and extended layouts. The display-helper test mocks RandR and does not
change hardware modes.
The screenshot-helper test verifies region capture uses slop's no-OpenGL path and
that cancellation saves or copies nothing. The Dunst theme test checks the Aero palette,
square/opaque styling, font, geometry, urgency timeouts and click actions without starting
a notification daemon. The lock-helper test checks foreground
waiting, image cleanup, conversion-failure fallback, inherited suspend FD and
duplicate prevention using a mock locker.

## Start icon smoke test

`icon-probe.c` verifies the stowed `tux-start` asset resolves through GTK's
standard hicolor icon theme, without a generated VAX theme:

```sh
probe_dir=$(mktemp -d /tmp/tux-icon-probe.XXXXXX)
gcc -Wall -Wextra tests/icon-probe.c \
  $(pkg-config --cflags --libs gtk+-3.0) -o "$probe_dir/gtk3-probe"
XDG_DATA_DIRS="${XDG_DATA_HOME:-$HOME/.local/share}:/usr/local/share:/usr/share" \
  timeout 5s xvfb-run -a "$probe_dir/gtk3-probe"
```

It should print the `icons/hicolor/32x32/apps/tux-start.png` path.
