# Configuration audit

Read-only snapshot, 2026-10-15. Stow deploys only `dotfiles/` and always excludes
the two PCManFM files below. “Deployed” does not prove an application uses a file;
absence of a repository reference does not prove it is unused. Nothing was removed.

| Path/group | Evidence and deployment | Classification / recommendation |
| --- | --- | --- |
| `.xinitrc`, `.bash_profile`, `.config/X11/`, `.config/awesome/` | Forwarding startx entry points, systemd user bus, Awesome config/autostart; deployed | Active; retain |
| `.local/bin/desktop-*`, `codex-usage`, `crypto-prices` | WM/sidebar/autostart callers; Stow-managed helpers | Active; retain. The `openbox-*` strings remaining in display/battery helpers are lock identities, not commands |
| `.config/picom/`, `dunst/`, `xsettingsd/`, `fontconfig/` | Autostart and theme/font integration; deployed | Active desktop configuration; retain |
| `.config/kitty/`, `btop/`, `libfm/` | Launcher/sidebar invokes kitty, btop and PCManFM; btop VAX config is repository-linked | Active application configuration; retain |
| `.config/pcmanfm/default/pcmanfm.conf`, `desktop-items-0.conf` | Live files are regular machine-local files; excluded by Stow; geometry, wallpaper and icon coordinates differ from repository | Machine-local; retain live files. Repository copies are reference/removal candidates, not deployable defaults |
| `.config/pcmanfm/default/desktop-items-1.conf` | Still repository-linked; Awesome does not start PCManFM desktop mode | Usage uncertain; confirm multi-monitor/desktop use before excluding or deleting |
| `.config/autostart/xfce4-clipman-plugin-autostart.desktop` | Deployed `Hidden=true` override | Intentional disabling policy, not unused autostart debris; retain |
| `.config/mpd/` | Autostart explicitly invokes MPD when installed; config deployed | Active integration; retain. Syncthing and conditional notes HTTP service are also intentionally preserved |
| `.config/zsh/`, `readline/`, `.bashrc`, `.config/tmux/`, `nvim/` | Shell configuration; vim aliases and EDITOR target nvim; configuration deployed | Active integrations; retain |
| `.config/vim/`, `mc/`, `tig/`, `fastfetch/`, `Code - OSS/`, `.lynxrc` | Stowed application configuration, including editor/CLI state; not necessarily invoked by the WM | External/usage uncertain; do not delete based on absent WM references. Vim config can still serve explicit Vim invocations despite nvim aliases |
| `.local/share/applications/firefox.desktop`, Audacious/MC skins, bundled fonts | Stowed application assets/launcher override, not old WM services | Application-managed usage; review preferences before removing |
| `configs/etc/zsh/zshenv` | Only remaining file in `configs/`; outside Stow package; sets ZDOTDIR | Manual system-wide reference; compare with `/etc/zsh/zshenv` before deciding whether to retain |
| `system/X11/xorg.conf.d/10-amdgpu.conf` | Outside Stow; installed counterpart exists; documented hardware-specific Xorg setup | Manual hardware reference; retain with X11 investigation docs; do not deploy automatically |
| Old Openbox/LXPanel/Hyprland/Waybar/Walker/Mako/cliphist/hyprlock/dwm/st config directories; `_old/`, `_remove/` | Absent from the current tree | Already removed; obsolete “retained configuration” documentation corrected. Historical Openbox crash references are not active launch commands |

## Concrete follow-up findings

- **Missing wallpapers:** `aurora-longhorn.png` and `win98-teal.svg` are absent
  both from the current asset directory and their deployed home paths. The checker
  still requires both. Awesome and `desktop-lock` reference the Aurora PNG;
  Awesome retains `lock-win98-tux.png` as fallback. Do not remove the Tux image as
  “legacy”: it is also a private-session fixture. Decide separately whether to
  generate/restore the desired assets or revise those expectations; no wallpaper
  behavior was changed here.
- **User-specific paths still deploy:** zsh's `.opencode` PATH, MC hotlist/panel
  directory, and Code's Python interpreter/Godot settings contain `/home/user/...`.
  These are portability review candidates, not evidence the applications are unused.
  The excluded PCManFM desktop reference also names an old Downloads wallpaper.
- **Machine-specific display settings:** `desktop-display` fixes AMD provider names,
  eDP/HDMI outputs, and preferred modes. Keep this intentional hardware profile;
  do not generalize it without another machine's requirements.
- **Autostart check:** current Awesome/X11 launchers reference no removed WM or
  Wayland daemon. The only deployed XDG autostart file is the Clipman disabling
  override. External NetworkManager and systemd services remain outside this audit.
- **Health report:** the real default and verbose checks both exit 1 for the two
  missing assets. Clipboard history is unavailable and Liberation Sans is used as
  the supported font fallback; these are warnings, not required failures.

Recommended cleanup order: resolve asset expectations first; then review the
machine-local PCManFM reference copies and per-application state with actual usage.
No additional deletion is justified solely by this inventory.
