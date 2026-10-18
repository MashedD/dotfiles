# Desktop reference

Commands below run from the repository root. See [the README](../README.md)
for the short installation and validation instructions.

This is the active desktop configuration for a CachyOS X11 session:

- AwesomeWM with four workspaces, floating-by-default windows (Win+Space toggles the current tag to tile) and Win98/Matrix titlebars
- Native Awesome 30px Win98/Matrix top panel and XEmbed tray, with snixembed bridge
- kitty, xfce4-appfinder, pcmanfm, Dunst with square-edged navy/Aero notifications and urgency accents, lxqt-policykit, and xss-lock/i3lock
- Adwaita GTK controls with blue selection, Breeze icons, and Adwaita cursors; VAX colors remain in terminals.
- HDMI-A-1-0 preferred at 2560×1440/144 Hz, with internal-display recovery

See the [configuration audit](config-audit.md) for references and deployment.
Shared X11 helpers use `desktop-*` names for volume, display, brightness,
screenshots and locking. Overrides use `DESKTOP_*` environment names.
Display/battery lock filenames retain their original identities to coordinate with
running processes.

## Screenshot status

![AwesomeWM](../screenshot.png)

Screenshot may differ from current progress.

## Install and deploy

`Documents/cachyos.md` is the original installation history. It is deliberately
not modified by this repository. Its desktop package section, plus local
`pacman -Qo` ownership checks, are the source for the required X11 dependencies:

```text
stow awesome xsettingsd snixembed
xorg-xrandr xorg-xset xclip xdotool maim
xss-lock i3lock dunst dmenu pcmanfm
gtk2 gtk3 adwaita-icon-theme breeze-icons fontconfig dbus util-linux
kitty xfce4-appfinder lxqt-policykit wireplumber brightnessctl
playerctl pavucontrol picom curl jq coreutils
```

Clipboard history is off by default. Run `DESKTOP_CLIPMENU_AUTOSTART=1 startx`
(or export it before starting Awesome) to opt into clipmenu autostart when both
`clipmenu` and `clipmenud` are installed. Manual launching remains available.
Standard application copy/paste and `xclip` screenshot copying are unaffected. Clipman's
XDG autostart entry is hidden for this profile, but manual launching is not
blocked. Microsoft Sans Serif is preferred; a weak fontconfig alias uses
Liberation Sans when the proprietary font is absent.

Optional application packages in the notes (games, development tools, office
software, and unrelated services) are not required by this desktop package.

Apply the Stow package first. Stow remains conflict-safe and never adopts an
existing file or symlink:

```sh
./stow.sh                 # dry-run preflight (same as ./stow.sh check)
./stow.sh apply           # preflight, then create/refresh Stow-owned links
./stow.sh unlink          # preflight, then remove only Stow-owned links
```

The GTK setup is intentionally simple: Adwaita controls and cursors, Breeze
icons, and the blue selection accent. The complete Tux Start image is a regular
Stow-managed hicolor asset; no separate theme-generation step or external theme
package is needed. The VAX palette remains available in terminals.

`desktop-check` is read-only: it checks Awesome syntax, commands, Adwaita GTK
controls/cursors, Breeze icons, blue selection, assets, fonts and helper executability.
Default output shows failures,
warnings and a summary; `desktop-check --verbose` also shows successful checks
and validator output. Required failures exit 1; optional warnings alone exit 0.
`desktop-check --runtime` additionally queries the current X display and Awesome,
then checks required session services for the current user. It skips runtime checks
when `DISPLAY` is unset; a missing optional SNI bridge is a warning. It
never installs packages, starts services, sends notifications, or changes settings.

The checker expects Microsoft Sans Serif or its Liberation Sans fallback
(for the Win98 UI) and the bundled FiraCode Nerd Font after Stow deployment.

Mutable MC/PCManFM state is not part of the Stow package: MC's `panels.ini` and
`hotlist`, plus PCManFM's `default/pcmanfm.conf`, `desktop-items-0.conf` and
`desktop-items-1.conf`, stay as regular local files. No exclusion rules are needed;
all conflicts for files actually in the package still fail without adoption.

Their one-time detachment backup is stored under
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/backups/<timestamp>-app-state-*/`.
`contents/` holds dereferenced file contents with permissions, `entries/` preserves
original files/symlinks, and `manifest.json` records link targets and modes. To
restore personal state, copy the relevant `contents/` entry back as a regular local
file only after checking/backing up newer changes. Do not restore dangling old
symlinks to source files that have been removed.

The one-time ownership migration backs up the existing btop configuration and
three repository-pointing absolute symlinks under
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/backups/<timestamp>/` before linking
them through Stow. To roll back those four entries, remove their deployed symlinks
and copy the corresponding backup entries back with `cp -a` (preserve symlinks).
Never overwrite a regular file during rollback. No session restart is automatic.

## Starting and validating Awesome

`startx` starts Awesome through `~/.config/X11/xinitrc`; `~/.xinitrc` also
forwards there when the login shell has not exported `XINITRC`. The session
uses the existing systemd user D-Bus bus. Do not wrap it in `dbus-run-session`.
Save work and log out of the old WM before running `startx`; deployment does
not replace or kill a live WM.

Awesome's built-in wibar replaces LXPanel **at the top, 30px high**, with
a Frutiger Aero sky-blue glass gradient, a green Tux Start button, a left-aligned
Longhorn-style glass Start menu (Start button or bare Win tap), and consistently
styled display/window menus. Each actionable Start-menu entry has a unique
underlined letter mnemonic; press it while the menu is open to launch that entry
immediately (for example, **Q** for Quake 1 and **U** for Quake 2). Clicking outside
the menu or elsewhere on the top bar dismisses it; the Start button still toggles it.
Arrow/Enter navigation remains available.
It also has four-workspace buttons (scroll up = previous workspace; scroll down = next),
current-workspace taskbar (including minimized windows),
CPU graph, battery status, volume, tray and `Fri  DD.MM.YY  HH:MM:SS` clock
(localized abbreviated weekday, fixed width, bold 9pt text, one-second updates). Click the
clock for a Monday-first calendar; hover CPU/battery/clock for details.
Volume: left-click opens pavucontrol, right/middle-click mutes, scroll changes
volume using the same helper as the media keys. The complete 65×25 Start image
is rendered at native size without a duplicate text label. The native systray appears only
on the primary monitor; snixembed bridges SNI applications. LXPanel is no
longer autostarted. All normal/dialog windows still float with click-to-focus.
The selected wallpaper (bundled cabin PNG by default) is rendered by
`gears.wallpaper` and reapplied on monitor
geometry changes; neither feh nor a wallpaper daemon is started.

```sh
awesome -k -c ~/.config/awesome/rc.lua
python3 tests/test-awesome-session.py  # private Xvfb/D-Bus; no live-session changes
```

Win+P opens a display menu centered on the focused screen: internal only, HDMI
only, extended desktop, or automatic hotplug layout. The Start menu's **Control
Panel** edits GTK theme, icon/cursor theme, interface font, selection colors,
toolbar and image preferences, sound/animation toggles, and Xft font rendering.
Apply saves `xsettingsd.conf` and GTK 3 `settings.ini`, then restarts only
xsettingsd; failed restarts roll the files back. Its Tools tab also offers the
same four display profiles as Win+P, launches ArandR for manual layout edits,
starts btop or htop in Kitty, launches the AMDGPU TOP GUI and XFCE Task Manager,
and opens Pavucontrol, NetworkManager, Bluetooth Manager, Power Manager settings,
or Solaar on demand. The Sidebar tab follows Appearance and configures section
visibility, weather city and coordinates, to-do/calendar Markdown paths, wallpaper
folders, the document-editor command, and News-browser command. A separate Quick
Launch tab manages its complete launcher list; News settings are managed in the
following News tab. Sidebar preferences are stored outside Stow at
`$XDG_CONFIG_HOME/desktop-control-center/sidebar-preferences` (default
`~/.config/desktop-control-center/sidebar-preferences`). Editor commands may use
`{file}` and browser commands `{url}`; if omitted, the path or URL is appended.
Both run as argv without a shell; a blank editor command uses the system default.
The launcher list is stored
at `$XDG_CONFIG_HOME/desktop-control-center/quick-launch.json`. Existing launchers
are the initial defaults, but the list can be edited, reordered, enabled/disabled, or
replaced. Commands are parsed as argv and never run through a shell; for example,
`kitty mdn-editor -- ~/Documents/notes.md` adds a Notes shortcut. Quick Launch is
hidden by default to save space. Use **Save & Restart Awesome** in either settings
tab, or save choices and press Win+Ctrl+R to apply them. Solaar is not
started automatically. The Start menu keeps
its Volume Control entry but no longer duplicates Monitor or Display outputs.
The sidebar also has a scrollable News inbox (default view: unread) backed only by
curated RSS/Atom sources. Its non-modal reader opens beside the sidebar at full
available screen height, with responsive wheel scrolling and a draggable scrollbar;
Open toggles to Close, the X closes explicitly, and outside clicks/Escape leave it open.
The Control Center's Sidebar tab toggles News visibility;
its News tab edits category names and multiple feed sources per category, including
URLs, labels, enabled state, and a bounded feed test. New profiles start with no
categories or feeds. Existing profiles migrate their four current category filters
and Wykop General source once. Mutable settings are stored atomically at
`$XDG_CONFIG_HOME/desktop-news/config.json` (default
`~/.config/desktop-news/config.json`), outside the Stow-managed Awesome directory;
`~/.config/awesome/news-feeds` is only a legacy migration input. Stories open with
the configured browser command and are marked read; individual read/unread/remove
controls and **Mark all
read** are available. Inbox state is stored under `$XDG_STATE_HOME/awesome/news.json`
(default `~/.local/state/awesome/news.json`). No scraping or ranking is used.
Trash and the integrated volume control are in System Status. Explicit HDMI modes prefer 2560×1440/144 Hz; the
internal display stays enabled until a requested mode succeeds. Mouse: drag
titlebar to move, double-click to maximize, and drag a maximized titlebar to restore
it beneath the pointer. Releasing a titlebar drag at the top edge maximizes; releasing
at a left/right edge snaps to that workarea half (top wins at corners). A click alone
does not unmaximize. Win+left-drag moves, Win+right-drag resizes. Titlebars have
icon, title, an ↑ always-on-top toggle, minimize, maximize and
close. The ↑ button stays pressed while enabled and its tooltip reports the state;
it does not make the window sticky or move it between workspaces. Alt+Space/right-click title opens window actions. Win+Left/Right snaps
a window to a screen half. Alt+Tab/Shift+Alt+Tab cycles; Alt+F4 closes;
Alt+F11 toggles fullscreen. Win+D toggles show-desktop. Ctrl+Alt+arrows switches
workspaces without wrapping; Win+Shift+arrows focuses directionally.
Win+Ctrl+R reloads Awesome without duplicating session services; **Win+Shift+Q
opens a centered Quit/Cancel confirmation**. Desktop right-click and the native
Start button show the daily-tools
menu; Applications opens Awesome's built-in application launcher, and Run
opens xfce4-appfinder. Openbox-specific edge-resize/shade controls are not emulated;
use Win+right-drag anywhere or plain left-drag on the bottom-right grip for
resizing. Maximized/fullscreen windows hide the resize strip and borders;
unmaximizing restores them. The top panel hides only while a fullscreen window is visible on that monitor's
selected workspace(s). Switching away restores the panel and reserved sidebar;
switching back hides them again, without exiting the application's fullscreen.
Minimizing or closing the fullscreen window also restores the controls.

## AMD Xorg crash investigation (this laptop)

The October 6, 2026 10:10 crash was an AMD iGPU GPU-memory fault followed by
`gfx_0.0.0` timeout and Xorg SIGABRT in Mesa (`libgallium`) through Glamor.
The October 1 and October 8 crashes had the same fault/timeout on the dGPU.
The failure persisted on `7.2.9-1-cachyos` during ordinary desktop use and
recurred on `6.18.55-1-cachyos-lts` on October 9. LTS did not fix it.
This is not an Openbox crash; the exact underlying Mesa/kernel defect is not
yet identified.

See [the X11 stability trial](x11-stability.md) for preserved evidence,
a controlled LTS-kernel test, boot-entry verification, acceptance checks and
recovery. LTS has now been boot-tested and failed; see the
[crash report draft](x11-crash-report.md) for both-kernel evidence.
No further speculative graphics changes are being applied.

## UEFI boot-menu output on external HDMI

Read-only inspection on the MSI Bravo 15 B7ED (BIOS `E158PAMS.103`) found
systemd-boot 262 and the current `linux-cachyos.conf` entry. The firmware reports
American Megatrends UEFI 2.80/build 5.24. `efibootmgr` lists the normal Linux Boot
Manager and fallback entries; these entries do not configure a video connector.

The UEFI `ConOut` and `ConOutDev` variables contain the same ACPI/PCI display path.
Its PCI route follows the iGPU-side `00:08.1` path rather than the discrete Radeon
`03:00.0` route. The ACPI ADR node was not mapped to a physical connector, so this
records the current firmware console path but does not by itself determine all
available outputs. After Linux starts, DRM reports HDMI on the discrete GPU and eDP
on the iGPU; that runtime topology does not reveal firmware GOP routing.

The user recalls that the systemd-boot menu was previously visible on the external
monitor after an unrecorded firmware setting change. It later returned to the prior
default, possibly after a firmware update; neither the setting nor the cause of the
reversion is independently known. This history means external boot-menu output has
worked at least once and should be treated as a recoverable configuration, not a
firmware limitation.

The EFI system partition and loader configuration are not readable by the current
user: `bootctl status` reports the active loader/entry but exits with a permission
warning, and `bootctl list` cannot read `loader.conf`. No matching Bravo 15 B7ED
firmware manual was found in the local documentation/download directories. During
this firmware investigation, no EFI files, firmware settings, or persistent boot
arguments were changed. The later one-boot `fbcon=map:1` test affects Linux console
mapping after kernel startup, not the systemd-boot menu.

**Conclusion:** the current firmware console path is iGPU-side, while the user
reports a prior successful external-menu configuration. The exact setting remains
unknown. During a future, user-chosen firmware visit, photograph or record the current
display/graphics settings, then test only a clearly relevant option
one at a time and record its menu path and value. Check BIOS version/change notes before
attributing the reversion to an update. No firmware setting was changed here.

## Linux text console on HDMI

A one-boot test confirmed that `fbcon=map:1` sends Linux text consoles to HDMI, and
switching virtual consoles works there. On this system `fb0` is the iGPU/internal-panel
framebuffer and `fb1` is the discrete-GPU/HDMI framebuffer. This helps with TTY access
if X exits while the dGPU display link remains usable; it does not prevent X crashes
or move the UEFI/systemd-boot menu.

To keep the parameter through kernel updates, use the CachyOS `sdboot-manage`
configuration source rather than editing only a generated entry. The installed
`sdboot-kernel-update` hook runs `sdboot-manage autogen`; the manager loads
`/etc/sdboot-manage.conf.d/*.conf` after `/etc/sdboot-manage.conf` and regenerates
generated entries. The current manager configuration overwrites existing kernel
entries, so a direct edit to `/boot/loader/entries/linux-cachyos.conf` can be lost on
a later kernel update. The persistent source is an `/etc` drop-in.

After reviewing current entries and backing them up, create the drop-in:

```sh
sudo bootctl list --no-pager
backup="/root/loader-entries.pre-fbcon.$(date +%Y%m%d-%H%M%S)"
sudo cp -a /boot/loader/entries "$backup"
printf 'Boot-entry backup: %s\n' "$backup"
sudo install -d -m 755 /etc/sdboot-manage.conf.d
sudoedit /etc/sdboot-manage.conf.d/99-fbcon.conf
```

Put these two lines in the file:

```sh
LINUX_OPTIONS+=" fbcon=map:1"
LINUX_FALLBACK_OPTIONS+=" fbcon=map:1"
```

The first covers normal generated kernel entries; the second covers generated
fallback-initramfs entries. Regenerate the current entries from that persistent
source, then verify the parameter appears in the intended entries:

```sh
sudo /usr/bin/sdboot-manage autogen
sudo bootctl list --no-pager
sudo grep -H -o 'fbcon=map:1' /boot/loader/entries/*.conf
```

`autogen` rewrites generated kernel entries, so inspect for any manually maintained
options before running it; record the backup directory name and do not reboot unless
`bootctl list` still shows the expected entries. Do not run `setup` or reinstall the
bootloader. After the next planned reboot, verify the parameter with
`grep -o 'fbcon=map:1' /proc/cmdline` and switch to another VT to confirm HDMI still
shows the console. To remove the setting, delete the drop-in and regenerate:

```sh
sudo rm /etc/sdboot-manage.conf.d/99-fbcon.conf
sudo /usr/bin/sdboot-manage autogen
```

This removes the parameter from regenerated entries while retaining the remaining
configured options.

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
apply Xorg driver options. The installed `linux-cachyos-lts` kernel was tested
and reproduced the crash; do not treat selecting it as a fix.

The display helper now uses `xrandr --current` to read hotplug-updated server
state without hardware/EDID probing on every poll (the previous Xorg log
had grown to 47 MB). This reduces unnecessary driver activity; it is not
proof that polling caused the GPU faults. Since faults also persist on LTS,
preserve fresh journal/core evidence and use the report draft for
maintainer-guided driver isolation; avoid partial Arch package upgrades.

## Shortcuts

- Win+1–4: switch desktop; Win+Shift+1–4: move focused window and follow
- Win+Enter: kitty; Win+R: application finder; Win+E: pcmanfm
- Win+L: lock screen; Win+P: output menu; Win+Shift+Q: confirmed quit
- Win+S: sidebar keyboard navigation; Win+Shift+S: cycle sidebar visibility modes
- Print: full screenshot; Alt+Print: focused window; Shift+Print: selected region
- Media and brightness keys use the shared desktop helpers
- Awesome desktop menu: **Reapply Display Layout** runs the same serialized layout pass

### Less-obvious controls

| Action | Shortcut or gesture |
| --- | --- |
| Toggle floating/tiled layout for the current desktop | Win+Space |
| Move/resize a window from anywhere | Win+left-drag / Win+right-drag |
| Restore a maximized window and snap it | Drag its titlebar; release at the top to maximize or at a side to snap half-screen |
| Open window actions | Alt+Space or right-click the titlebar |
| Navigate the visible sidebar | Win+S; Escape exits; application-only keys are not replayed |
| Toggle Start menu without selecting another shortcut | Tap and release Win |
| Reload Awesome | Win+Ctrl+R |

Screenshots are captured into `~/Pictures/Screenshots` only after a successful
capture, then copied to the clipboard. A cancelled region selection leaves
existing clipboard contents and saved screenshots unchanged; a clipboard
failure keeps the saved PNG and prints its path.

## Sidebar data freshness

Codex quotas are snapshots refreshed every minute, not a live guarantee of remaining
capacity. The card hides percentages, bars and reset credits if a request fails,
source metadata is missing, or the confirmed source sample expires (120 seconds).
The hover tooltip's last-success time is the source confirmation time—not the time
an old cache was read. A real 0% remaining is shown as 0%, never treated as missing.
Reload Awesome with Win+Ctrl+R after updating to enable this display safety logic.

`codex-usage` and `crypto-prices` now use kernel-managed `flock` locks in `.flock`
files, so termination cannot leave a permanent directory-lock blockade. Old `.lock`
directories are ignored, not recursively deleted. Fresh human/tmux output formats
are unchanged; failed/expired fallbacks are explicitly marked `C*` / `STALE`.
Awesome uses the versioned `--sidebar-data` TSV channel, carrying freshness status
and the original confirmation timestamp. Reading fallback data cannot renew its age.
Crypto and weather may retain last-known values with a visible STALE badge; quota
history is never presented as current headroom. Codex hover details include the
last source-confirmation time and the current failure/expiry reason. Codex app-server
fetches have a 12-second total budget (`CODEX_USAGE_FETCH_TIMEOUT`) and a
5-second per-transport cap (`CODEX_USAGE_TIMEOUT`), leaving time for stdio fallback
beneath Awesome's outer 20-second command timeout; transport process groups are
terminated and reaped on completion/cancellation. The 120-second
source-age policy is shared by parsing and collector stale state. Other status
collectors read their existing direct sources and do not use these on-disk helper
caches.

## Sidebar keyboard navigation

**Win+S** enters/exits navigation on the focused screen; **Escape** exits. A green
inset outline identifies the selected control without changing window focus.
The sidebar must already be visible: use Win+Shift+S first if hidden. A visible
sidebar below windows is raised temporarily; exit restores its current mode's
stacking without changing struts or window geometry. Entry is refused during
fullscreen or another input grab.

Navigation is **modal**: press Escape before typing or using application-only
shortcuts. Unrecognized application input is ignored, never replayed. Existing
WM shortcuts (including Alt+Space, workspace, media, lock, and quit shortcuts)
exit navigation and run their original callbacks. A bare Win tap exits and opens
Start. No synthetic keystrokes or modifier changes are used.

- Tab/Shift+Tab move between controls and wrap; Up/Down do likewise outside the
  calendar grid. Home/End select the first/last control outside the grid.
- Enter/Space activate controls. Section headers fold/expand; Left/Right explicitly
  collapse/expand them. Local adjustments retain navigation. Opening an app or
  document, opening the mixer, or requesting Sleep exits first.
- On volume: Left/Right adjust, Space toggles mute, Enter opens the mixer.
- The calendar grid is one focus stop. Left/Right select a day; Up/Down select a
  week. Page Up/Down change month, clamping the day if needed; Home selects today,
  End selects the month's last day. Enter/Space opens `calendar.md`. Date changes
  update the displayed events immediately. Clicking a listed TODO item or
  calendar event opens its Markdown document with the registered desktop handler;
  date cells select dates, and section headings fold/expand. Month-arrow buttons
  remain separate.
  When the local day changes, the next existing one-minute refresh selects today,
  shows its month and events, even during browsing or keyboard navigation. This
  also catches up after suspend. Later same-day refreshes preserve your selection;
  hidden sidebars and folded calendars stay hidden/folded.
- Offscreen controls scroll into view. Folded sections expose their headers (and
  the System Status header's Trash link); navigation follows the current section
  order. Calendar refreshes keep a valid focus target.

Mouse interaction, application focus/workspace changes, hiding, fullscreen, and
screen removal/geometry changes end navigation. Selection is not persisted;
normal calendar/fold/scroll changes remain as with mouse use. Section reordering
and scrollbar dragging remain mouse operations. No new service or dependency is
required.

## Session behavior and reloads

Awesome autostart preserves the existing systemd user D-Bus session, leaves
the externally managed NetworkManager applet untouched, uses Awesome's native
tray as the sole owner, and leaves removable-drive handling unchanged. The display watcher is asynchronous,
single-instance, polls every three seconds, and exits if the X server vanishes.
The same Openbox session services are retained: xsettingsd, display watcher,
battery alerts, snixembed, dunst, lxqt-policykit, and xss-lock. Solaar is not
started by this profile; manual launching remains available. Logitech mouse
battery status is shown in the sidebar. Syncthing, MPD and the conditional notes HTTP server from the old
xinitrc are also retained. Only LXPanel and feh are replaced by built-in widgets
and wallpaper rendering. User applications that were not autostarted before
(e.g. Firefox/Gajim) are not newly autostarted.

Win+L and xss-lock share the lock helper. It passes the sleep descriptor to
i3lock, waits until unlock, prevents competing lock instances, uses a private
temporary image of the selected/default wallpaper and removes it afterward. If conversion fails, it still
locks with Win98 teal. The ten-minute X11 idle timer and suspend locking remain.

After changing deployed configuration:

```sh
awesome-client 'awesome.restart()'
dunstctl reload
```

A new login starts the autostart services; do not launch duplicate panel,
notification, clipboard-manager, display-watcher, or lock daemons manually.
