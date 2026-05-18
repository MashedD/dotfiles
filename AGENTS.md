# AGENTS.md — dotfiles project

## System

- WM: **Hyprland** (NOT dwm — dwm config at `configs/dwm/` is old/leftover)
- Terminal: kitty
- Launcher: walker
- File manager: pcmanfm
- Bar: waybar
- Wallpaper: hyprpaper
- Notifications: mako
- Clipboard: cliphist
- Auth: hyprlock

## Hyprland Rules — CRITICAL

- `windowrulev2` is **deprecated** — causes parse errors.
- `windowrule` v2 syntax (`windowrule = float, class:^(Foo)$`) **also causes errors** on current Hyprland version — `$` clashes with Hyprland variable prefix.
- **Use old-style `match:` syntax only:**
  - `windowrule = match:class ^(Foo|Bar)$ float`
  - `windowrule = match:title ^(Some Title)$ float`
- No combined class+title in one rule. Use separate rules per pattern.

## Theme: Win98 + Matrix

Combine Windows 98 aesthetic + neon green Matrix.

### Matrix shader
`dotfiles/.config/hypr/shaders/matrix.glsl`
Toggle with: `$mainMod SHIFT M` / `$mainMod SHIFT N`

### Border colors (already in hyprland.conf)
```
col.active_border = rgba(001a00ff) rgba(00ff41ff) 270deg
col.inactive_border = rgba(202020ff) rgba(004400ff) 270deg
```

### Win98 window rules
Float for: modal dialogs, file dialogs, confirmations, preferences, properties calculators, volume controls, Pidgin windows, gajim

### General look
- Zero gaps (`gaps_in = 0`, `gaps_out = 0`)
- Zero border (`border_size = 0`) — only colored borders on active
- Zero rounding
- No blur
- No shadow on tiled (shadow on floating enabled)
- No animations (disabled)

## Directories

| Path | Purpose |
|------|---------|
| `configs/` | Legacy configs (dwm, st, etc.) |
| `dotfiles/` | Current dotfiles managed by some tool |
| `_old/` | Abandoned experiments |

## TODOs / Future

- Clean up `configs/dwm/` leftovers
- Keep Win98-Matrix shader as default toggle
