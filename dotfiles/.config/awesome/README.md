# Awesome components

`rc.lua` composes the session, window rules, titlebar controls, and menus.
`appearance.lua` owns shared palettes, gradients, opacity, and status thresholds.
`titlebar-layout.lua` prioritizes Close on narrow windows, omitting always-on-top,
minimize, then maximize as width runs out; the icon disappears below 62px. Normal
button sizes/spacing remain intact where they fit. Alt+Space retains every action;
no minimum client width is imposed. Omitted controls cancel presses and tooltips.
`fullscreen-geometry.lua` separates fullscreen return state from Awesome 4.3's
native maximize history. It delegates other geometry contexts unchanged, coalesces
refits, and fits monitor-moved windows without replacing their native maximize
restore history. Native stacking policy is unchanged (Awesome itself clears
`ontop` when entering fullscreen); no extra sticky/always-on-top policy is added.
`interaction.lua` provides a release-to-activate state machine, deduplicated button
bindings, shared mouse-grab ownership, elapsed-time transitions, and lifetime groups that
disconnect signals and cancel delayed tooltips.

`sidebar.lua` remains the screen-level coordinator: sections, persistence, collector
subscriptions, launch actions, and section reordering. `sidebar-data.lua` shares
session samples and only notifies on visible state/value changes; a separate shared
clock tick performs no system probes. Widget setters skip identical rendered values,
and system-status layout is invalidated only when optional readings appear/disappear.
`sidebar-battery.lua` uses Gio async reads for slow laptop capacity files; the same
one-second stats collector waits without blocking the main loop. Pending requests
do not overlap, become stale normally, and are cancelled when the last subscriber
leaves; late callbacks cannot update a replacement collector generation. Missing
capacity values still remove that battery from the sample, as before.
`sidebar-keyboard.lua` owns modal Win+S navigation; `sidebar-keyboard-view.lua`
adapts native grabs, clipped focus outlines, scrolling and lifecycle cancellation.
`keyboard-shortcuts.lua` dispatches the existing WM callbacks without synthesizing
input; application-only input requires Escape first. Calendar keyboard arithmetic
lives with the calendar component. See [keyboard usage](../../../docs/desktop.md#sidebar-keyboard-navigation).
`sidebar-launch.lua` rechecks executable availability on hover/click and reports
immediate failures without disabling entries or waiting for application exit.
`menu-release.lua` adapts native `awful.menu` entries with an in-content pressed overlay
and activates only on a valid left-button release inside the same item; keyboard
navigation and right-click dismissal remain native. Start uses a generated darkened image while held and toggles its menu
only on release inside. Workspace actions use the shared grab/release handler and an
immediate, fading dark-teal overlay that preserves native taglist backgrounds. The
coordinator adapts component handles back to existing `s.sidebar_*` diagnostics;
document formats and persisted state are unchanged.

| Component | Constructor inputs | Returned operations/handles |
| --- | --- | --- |
| `sidebar-clock.lua` | appearance, label/card factories, interaction, dismiss and mode callbacks | widget, analog/digital/date widgets, set_mode, toggle, tick, destroy |
| `sidebar-calendar.lua` | appearance, label/section factories, document path, interaction, open/blocked/entry callbacks, button surfaces | widget, grid, navigation widgets, refresh, select_date, shift_month, selected_date, month, day_cells, destroy |
| `sidebar-scroll.lua` | appearance, screen, content/header/clock widgets, width, panel accessor, interaction, offset/click-suppression callbacks | column/view/bar/bar-panel widgets, set_offset, scroll_by, offset/max, thumb_geometry, attach, cancel_drag, destroy |

Components have idempotent `destroy()` methods and no persistent state. The parent
registers those methods in its lifetime group. Collector timers remain owned by
`sidebar-data.lua`; document refresh timers remain in the parent. Components do not
start desktop services or create independent polling loops for data. Release-bound
sidebar actions activate only after a valid left-button release inside the control;
Quick Launch availability is checked anew for each tooltip/click.

See `../../../tests/README.md` for syntax, Lua, isolated Xvfb, and private
Picom/XRender compositing checks. Compositor configuration preserves explicit ARGB
surfaces without blur, shadows, fading, inactive dimming, or imposed frame opacity.
