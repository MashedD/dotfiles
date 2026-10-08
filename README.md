# Openbox dotfiles

This is the active desktop configuration for a CachyOS X11 session:

- Openbox with four desktops and the external Chicago95 window theme
- LXPanel (VAX profile) as the only XEmbed tray owner, with snixembed bridge
- kitty, xfce4-appfinder, pcmanfm, dunst, clipmenu, lxqt-policykit, and xss-lock/i3lock
- Chicago95 controls with Matrix-green (`#001a00` / `#00ff41`) active states
- HDMI-A-1-0 preferred at 2560×1440/144 Hz, with internal-display recovery

The repository also retains legacy Hyprland, Waybar, Walker, Mako, hyprlock,
dwm, and st files for reference. They are not started by the active session.

## Screenshot status

![Obsolete Hyprland desktop](screenshot.png)

The image above is an **obsolete Hyprland desktop reference**, not a picture of
the current Openbox session. Current screenshots are intentionally not claimed
until one is captured from this setup.

## Install and deploy

`Documents/cachyos.md` is the original installation history. It is deliberately
not modified by this repository. Its desktop package section, plus local
`pacman -Qo` ownership checks, are the source for the required X11 dependencies:

```text
stow openbox lxpanel xsettingsd snixembed
xorg-xrandr xorg-xset xclip xdotool maim
xss-lock i3lock dunst clipmenu dmenu pcmanfm
gtk2 gtk3 fontconfig dbus util-linux
kitty xfce4-appfinder lxqt-policykit wireplumber brightnessctl
playerctl pavucontrol
```

Optional application packages in the notes (games, development tools, office
software, and unrelated services) are not required by this desktop package.

Apply the Stow package first. Stow remains conflict-safe and never adopts an
existing file or symlink:

```sh
./stow.sh                 # dry-run preflight (same as ./stow.sh check)
./stow.sh apply           # preflight, then create/refresh Stow-owned links
./stow.sh unlink          # preflight, then remove only Stow-owned links
```

Chicago95 remains an external installation. Then generate the VAX overlay and
named panel icon separately:

```sh
./setup-vax-theme
./setup-vax-theme --path "/path/to/Chicago95"
~/.local/bin/openbox-check
```

The helper searches standard user and system theme directories, writes the
generated VAX theme to `${XDG_DATA_HOME:-~/.local/share}/themes/VAX`, and keeps
the GTK2 controls and a GTK3 Matrix-green selection wrapper. It creates a
compatibility `~/.themes/VAX` symlink only when that path is absent or is the
old repository-owned VAX symlink. Unmarked themes, files, icon paths, and
unrelated symlinks are refused. Re-run it after updating Chicago95.

`openbox-check` is read-only: it reports required and optional commands,
assets, fonts, generated theme files, and helper executability. It never
installs packages, starts services, or changes settings.

The checker expects Microsoft Sans Serif (for the Win98 UI) and the bundled
FiraCode Nerd Font to be visible to fontconfig after Stow deployment.

## AMD Xorg crash workaround (this laptop)

The October 6, 2026 10:10 crash was an AMD iGPU GPU-memory fault followed by
`gfx_0.0.0` timeout and Xorg SIGABRT in Mesa (`libgallium`) through Glamor.
The October 1 crash had the same fault/timeout on the dGPU. This is not an
Openbox crash; the exact underlying Mesa/kernel defect is not yet identified.

Disabling Glamor was tested and **broke HDMI**: both RandR providers advertised
`cap: 0x0`, preventing the dGPU output provider from attaching to the iGPU.
Do not use `AccelMethod "none"` on this hybrid-GPU setup.
`system/X11/xorg.conf.d/10-amdgpu.conf` now preserves acceleration and the
original working layout; it is hardware-specific and not Stowed. It does not
claim to fix the underlying GPU fault.

From the repository root, with the X session stopped:

```sh
sudo cp -a /etc/X11/xorg.conf.d/10-amdgpu.conf \
  /etc/X11/xorg.conf.d/10-amdgpu.conf.bak-$(date +%Y%m%d-%H%M%S)
sudo install -m 644 system/X11/xorg.conf.d/10-amdgpu.conf /etc/X11/xorg.conf.d/10-amdgpu.conf
startx
```

After starting X, verify nonzero provider capabilities and HDMI visibility,
then test kitty, HDMI hotplug, internal-panel fallback and locking:

```sh
xrandr --listproviders
xrandr --current
journalctl -k -b --since today | grep -E 'page fault|ring .*timeout|Process Xorg'
```

To undo the failed October 6 workaround, restore the known working backup:

```sh
sudo cp -a /etc/X11/xorg.conf.d/10-amdgpu.conf.bak-20261006-101509 /etc/X11/xorg.conf.d/10-amdgpu.conf
```

Save work and log out before restarting X. `openbox --reconfigure` cannot
apply Xorg driver options. The installed `linux-cachyos-lts` kernel is the
next stability test: select it in the boot menu after restoring this config.
Its effect on the intermittent crash still needs observation.

The display helper now uses `xrandr --current` to read hotplug-updated server
state without hardware/EDID probing on every poll (the previous Xorg log
had grown to 47 MB). This reduces unnecessary driver activity; it is not
proof that polling caused the GPU faults. If faults persist, preserve fresh
journal/core evidence and test a supported LTS kernel with an up-to-date,
matched Mesa/firmware stack; avoid partial Arch package upgrades.

## Shortcuts

- Win+1–4: switch desktop; Win+Shift+1–4: move focused window and follow
- Win+Enter: kitty; Win+R: application finder; Win+E: pcmanfm
- Win+V: clipboard history; Win+L: lock screen
- Print: full screenshot; Alt+Print: focused window; Shift+Print: selected region
- Media and brightness keys use the Openbox helper bindings
- Openbox menu: **Reapply Display Layout** runs the same serialized layout pass

Screenshots are captured into `~/Pictures/Screenshots` only after a successful
capture, then copied to the clipboard. A cancelled region selection leaves
existing clipboard contents and saved screenshots unchanged; a clipboard
failure keeps the saved PNG and prints its path.

## Session behavior and reloads

Openbox autostart preserves the existing systemd user D-Bus session, leaves
the externally managed NetworkManager applet untouched, keeps LXPanel as the
sole tray owner, and leaves removable-drive handling unchanged. The display watcher is asynchronous,
single-instance, polls every three seconds, and exits if the X server vanishes.
The lock uses xss-lock's transferred sleep descriptor and an explicit ten-minute
X11 screensaver timeout.

After changing deployed configuration:

```sh
openbox --reconfigure
lxpanelctl restart
dunstctl reload
```

A new login starts the autostart services; do not launch duplicate panel,
notification, clipboard, display-watcher, or lock daemons manually.
