# Configuration audit

Audit and approved cleanup, 2026-10-15. Stow deploys only `dotfiles/`, without
special exclusions. “Deployed” does not prove an application uses a file; absence
of a repository reference does not prove it is unused. The five personal/state
files below were backed up and preserved locally before their source copies were removed.

| Path/group | Evidence and deployment | Classification / recommendation |
| --- | --- | --- |
| `.xinitrc`, `.bash_profile`, `.config/X11/`, `.config/awesome/` | Forwarding startx entry points, systemd user bus, Awesome config/autostart; deployed | Active; retain |
| `.local/bin/desktop-*`, `codex-usage`, `crypto-prices` | WM/sidebar/autostart callers; Stow-managed helpers | Active; retain. The `openbox-*` strings remaining in display/battery helpers are lock identities, not commands |
| `.config/picom/`, `dunst/`, `xsettingsd/`, `fontconfig/` | Picom config is retained for optional manual use; Dunst/xsettingsd remain session services; theme/font integration; deployed | Retain; Picom is intentionally not autostarted |
| `.config/kitty/`, `btop/`, `libfm/` | Launcher/sidebar invokes kitty, btop and PCManFM; btop VAX config is repository-linked | Active application configuration; retain |
| `.config/pcmanfm/default/pcmanfm.conf`, `desktop-items-0.conf`, `desktop-items-1.conf` | All three live files are regular machine-local files; repository copies removed after backup/detachment | Keep geometry, wallpaper and icon state local; not part of deployment |
| `.config/mc/panels.ini`, `.config/mc/hotlist` | Live panel state and personal bookmark preserved as regular files; repository copies removed after backup/detachment | Local state; MC menu, extension definitions and skins remain managed |
| `.config/autostart/xfce4-clipman-plugin-autostart.desktop` | Deployed `Hidden=true` override | Disables Clipman autostart for this profile; manual launching remains available |
| `.config/mpd/` | Autostart explicitly invokes MPD when installed; config deployed | Active integration; retain. Syncthing and conditional notes HTTP service are also intentionally preserved |
| `.config/zsh/`, `readline/`, `.bashrc`, `.config/tmux/`, `nvim/` | Shell configuration; vim aliases and EDITOR target nvim; configuration deployed | Active integrations; retain |
| `.config/vim/`, remaining `mc/` preferences, `tig/`, `fastfetch/`, `Code - OSS/`, `.lynxrc` | Stowed application configuration; not necessarily invoked by the WM | External/usage uncertain; do not delete based on absent WM references. Vim config can still serve explicit Vim invocations despite nvim aliases |
| `.local/share/applications/firefox.desktop`, Audacious/MC skins, bundled fonts | Stowed application assets/launcher override, not old WM services | Application-managed usage; review preferences before removing |
| `configs/etc/zsh/zshenv` | Only remaining file in `configs/`; outside Stow package; sets ZDOTDIR | Manual system-wide reference; compare with `/etc/zsh/zshenv` before deciding whether to retain |
| `system/X11/xorg.conf.d/10-amdgpu.conf` | Outside Stow; installed counterpart exists; documented hardware-specific Xorg setup | Manual hardware reference; retain with X11 investigation docs; do not deploy automatically |
| Old Openbox/LXPanel/Hyprland/Waybar/Walker/Mako/cliphist/hyprlock/dwm/st config directories; `_old/`, `_remove/` | Absent from the current tree | Already removed; obsolete “retained configuration” documentation corrected. Historical Openbox crash references are not active launch commands |

## Concrete follow-up findings

- **Wallpaper assets resolved:** the default is now the bundled `aurora-cabin.png`,
  copied byte-for-byte from the selected picture. Explicit wallpaper state remains
  authoritative and was not rewritten. The unused Aurora SVG was removed; the
  unlicensed `lock-win98-tux.png` wallpaper and its emergency fallback were
  removed. The cabin remains the single bundled wallpaper.
- **GTK theme cleanup:** the inactive VAX GTK generator/templates and its generated
  user theme were removed. GTK now uses Adwaita controls/cursors, Breeze icons and
  blue selection. The Tux Start asset is directly Stow-managed in hicolor; terminal
  VAX palettes are unchanged.
- **Approved path/state cleanup completed:** opencode's zsh PATH uses `$HOME`;
  the old `HYPRSHOT_DIR` export is removed. MC panel state/hotlist and all three
  PCManFM state files stay local, with contents and symlink metadata backed up as
  described in [deployment details](desktop.md#install-and-deploy). Code no longer
  globally pins one project's Python interpreter or auto-approves the absolute
  Godot path. Its existing `make` approval and other settings remain unchanged.
- **Machine-specific display settings:** `desktop-display` fixes AMD provider names,
  eDP/HDMI outputs, and preferred modes. Keep this intentional hardware profile;
  do not generalize it without another machine's requirements.
- **Autostart check:** current Awesome/X11 launchers reference no removed WM or
  Wayland daemon. The only deployed XDG autostart file is the Clipman disabling
  override. External NetworkManager and systemd services remain outside this audit.
- **Health report:** the two missing-default-asset failures are resolved by the
  bundled cabin image and corrected checker requirements. Clipboard history is
  off by default; users can opt into clipmenu autostart with
  `DESKTOP_CLIPMENU_AUTOSTART=1`. Ordinary copy/paste and screenshot-to-clipboard
  remain available. Liberation Sans is the supported font fallback.

No additional deletion is justified solely by this inventory. Further application
cleanup requires actual usage evidence; machine-specific display configuration is unchanged.
