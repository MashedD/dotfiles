# Awesome components

`rc.lua` composes the session, window rules, titlebar controls, and menus.
`appearance.lua` owns shared palettes, gradients, opacity, and status thresholds.
`interaction.lua` provides a release-to-activate state machine, button bindings,
and lifetime groups that disconnect signals and cancel delayed tooltips.

`sidebar.lua` remains the screen-level coordinator: sections, persistence, collector
subscriptions, launch actions, and section reordering. `sidebar-data.lua` shares
session samples and only notifies on visible state/value changes; a separate shared
clock tick performs no system probes. Widget setters skip identical rendered values,
and system-status layout is invalidated only when optional readings appear/disappear.
`sidebar-launch.lua` rechecks executable availability on hover/click and reports
immediate failures without disabling entries or waiting for application exit.
`menu-release.lua` changes native `awful.menu` entries to activate on a valid
left-button release inside the same item; keyboard navigation and right-click dismissal
remain native. The Start asset gains a dark glass overlay while held and toggles its menu
only on release inside; workspace left-click actions also run on release. The
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
