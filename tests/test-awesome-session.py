#!/usr/bin/env python3
"""Runtime smoke test on a private Xvfb server and private D-Bus bus.

Never starts the real session autostart or changes the live display layout.
"""
import os
import ctypes
import re
import signal
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "dotfiles/.config/awesome/rc.lua"


def main():
    if "--inside" not in sys.argv:
        return subprocess.call(["dbus-run-session", "--", sys.executable, __file__, "--inside"])
    processes = []
    with tempfile.TemporaryDirectory(prefix="awesome-smoke-") as directory:
        directory = Path(directory)
        logfile = directory / "awesome.log"
        testhome = directory / "home"
        helpers = testhome / ".local/bin"
        helpers.mkdir(parents=True)
        (testhome / ".local/share/wallpapers").mkdir(parents=True)
        shutil.copy2(ROOT / "dotfiles/.local/bin/openbox-lock", helpers / "openbox-lock")
        shutil.copy2(ROOT / "dotfiles/.local/share/wallpapers/lock-win98-tux.png",
                     testhome / ".local/share/wallpapers/lock-win98-tux.png")
        icon_source = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "icons/hicolor/32x32/apps/vax-tux-start.png"
        icon_target = testhome / ".local/share/icons/hicolor/32x32/apps/vax-tux-start.png"
        icon_target.parent.mkdir(parents=True)
        shutil.copy2(icon_source, icon_target)
        bin_dir = directory / "bin"
        bin_dir.mkdir()
        for name, source in {
            "wpctl": '#!/bin/sh\necho "Volume: 0.42"\n',
            "pavucontrol": '#!/bin/sh\necho mixer >> "$TEST_ACTIONS"\n',
        }.items():
            executable = bin_dir / name
            executable.write_text(source)
            executable.chmod(0o755)
        volume_helper = helpers / "openbox-volume"
        volume_helper.write_text('#!/bin/sh\necho "$1" >> "$TEST_ACTIONS"\n')
        volume_helper.chmod(0o755)
        env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", TEST_ACTIONS=str(directory / "actions"), AWESOME_TEST_MODE="1", NO_AT_BRIDGE="1", GIO_USE_VFS="local",
                   HOME=str(testhome), XDG_CONFIG_HOME=str(testhome / ".config"),
                   XDG_DATA_HOME=str(testhome / ".local/share"), XDG_RUNTIME_DIR=str(directory))
        lock_pids = []
        env.pop("XAUTHORITY", None)
        server = subprocess.Popen(["Xvfb", "-displayfd", "1", "-screen", "0", "1280x800x24",
                                   "-nolisten", "tcp", "-ac"], stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True)
        processes.append(server)
        try:
            number = server.stdout.readline().strip()
            assert number.isdigit(), "Xvfb failed to allocate a display"
            env["DISPLAY"] = ":" + number
            with logfile.open("w") as log:
                wm = subprocess.Popen(["awesome", "-c", str(CONFIG)], env=env,
                                      stdout=log, stderr=log)
                processes.append(wm)

                def lua(code):
                    result = subprocess.run(["awesome-client", code], env=env,
                                            capture_output=True, text=True, timeout=3)
                    assert result.returncode == 0, result.stderr
                    assert "Error" not in result.stdout, result.stdout
                    return result.stdout

                def wait(code, expected):
                    deadline = time.monotonic() + 8
                    last = ""
                    while time.monotonic() < deadline:
                        try:
                            last = lua(code)
                            if expected in last:
                                return last
                        except (AssertionError, subprocess.TimeoutExpired):
                            pass
                        time.sleep(0.1)
                    diagnostic = lua('local r=""; for _,c in ipairs(client.get()) do r=r..tostring(c.class)..":"..c.type..":"..c.x..","..c.y..","..c.width..","..c.height..":screen="..c.screen.index..":visible="..tostring(c:isvisible()); for k,v in pairs(c:struts()) do r=r..":"..k.."="..v end; r=r.."\\n" end; return r')
                    raise AssertionError(f"Expected {expected!r}: {code}\n{last}\n{diagnostic}\n{logfile.read_text()}")

                def press(keys):
                    subprocess.run(["xdotool", "key", "--clearmodifiers", keys], env=env,
                                   check=True, timeout=3)
                    time.sleep(0.15)

                wait('return #screen[1].tags', '4')
                assert 'floating' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                wait('return screen[1].workarea.y', '30')
                assert 'true' in lua('local p=screen[1].panel; return p.visible and p.height == 30 and p.position == "top"')
                assert 'true' in lua('local s=screen[1]; local b=s.sidebar; return b and not b.visible and s.workarea.width == s.geometry.width and b.x+b.width == s.geometry.x+s.geometry.width-2 and b.y == s.geometry.y+32 and b.height == s.geometry.height-34')
                press('super+shift+s')
                wait('return tostring(screen[1].sidebar.visible)', '"true"')
                press('super+shift+s')
                wait('return tostring(screen[1].sidebar.visible)', '"false"')
                wallpaper = subprocess.run(["xprop", "-root", "_XROOTPMAP_ID"], env=env,
                                           capture_output=True, text=True, check=True, timeout=3).stdout
                assert "PIXMAP" in wallpaper, wallpaper
                wait('return screen[1].panel_volume_text.text', '"42%"')
                assert 'true' in lua('local w=screen[1].panel_clock; return w.text:match("%d%d%.%d%d%.%d%d") ~= nil and w.text:match("%d%d:%d%d:%d%d") ~= nil and w.text:find(os.date("%a"), 1, true) ~= nil and w.forced_width == 170')
                lua('for _,b in ipairs(screen[1].panel_volume:buttons()) do if b.button == 4 then b:emit_signal("press") end end')
                lua('for _,b in ipairs(screen[1].panel_volume:buttons()) do if b.button == 3 then b:emit_signal("press") end end')
                lua('for _,b in ipairs(screen[1].panel_volume:buttons()) do if b.button == 1 then b:emit_signal("press") end end')
                time.sleep(0.3)
                actions = (directory / "actions").read_text().splitlines()
                assert all(action in actions for action in ("up", "mute", "mixer")), actions
                xlib = ctypes.CDLL("libX11.so.6")
                xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
                xlib.XOpenDisplay.restype = ctypes.c_void_p
                xlib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
                xlib.XInternAtom.restype = ctypes.c_ulong
                xlib.XGetSelectionOwner.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
                xlib.XGetSelectionOwner.restype = ctypes.c_ulong
                xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
                display = xlib.XOpenDisplay(env["DISPLAY"].encode())
                assert display
                try:
                    selection = xlib.XInternAtom(display, b"_NET_SYSTEM_TRAY_S0", 0)
                    assert xlib.XGetSelectionOwner(display, selection), 'Native tray has no XEmbed owner'
                finally:
                    xlib.XCloseDisplay(display)
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                press('Escape')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                subprocess.run(["xdotool", "mousemove", "1258", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].panel_calendar.visible)', '"true"')
                subprocess.run(["xdotool", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].panel_calendar.visible)', '"false"')
                desktops = subprocess.run(["xprop", "-root", "_NET_NUMBER_OF_DESKTOPS"], env=env,
                                          capture_output=True, text=True, check=True, timeout=3).stdout
                assert desktops.strip().endswith("= 4"), desktops
                for name in ("AwesomeSmokeA", "AwesomeSmokeB"):
                    processes.append(subprocess.Popen(["xmessage", "-name", name, "-geometry", "400x200", name],
                                                       env=env, stdout=log, stderr=log))
                wait('local n=0; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then n=n+1 end end; return n', '2')
                assert 'true' in lua('for _,c in ipairs(client.get()) do if c.class == "Xmessage" then assert(c.floating); assert(c._private.titlebars.top.args.size == 24); assert(c.y >= 30) end end; return true')
                subprocess.run(["xdotool", "mousemove", "84", "15", "click", "5"], env=env, check=True)
                wait('return screen[1].selected_tag.name', '"2"')
                subprocess.run(["xdotool", "click", "4"], env=env, check=True)
                wait('return screen[1].selected_tag.name', '"1"')
                press('super+2')
                wait('return screen[1].selected_tag.name', '"2"')
                press('super+1')
                wait('return screen[1].selected_tag.name', '"1"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then c:emit_signal("request::activate", "test", {raise=true}) end end')
                press('super+shift+3')
                wait('return client.focus and client.focus.first_tag.name', '"3"')
                wait('return screen[1].selected_tag.name', '"3"')
                size_before = lua('local c=client.focus; return c.width..","..c.height')
                old_width, old_height = map(int, re.search(r'"(\d+),(\d+)"', size_before).groups())
                coords = lua('local c=client.focus; return (c.x+c.width-5)..","..(c.y+c.height-4)')
                x, y = re.search(r'"(\d+),(\d+)"', coords).groups()
                subprocess.run(["xdotool", "mousemove", x, y, "mousedown", "1"], env=env, check=True)
                time.sleep(0.15)
                subprocess.run(["xdotool", "mousemove_relative", "--", "80", "50"], env=env, check=True)
                time.sleep(0.15)
                subprocess.run(["xdotool", "mouseup", "1"], env=env, check=True)
                assert 'true' in lua(f'local c=client.focus; return c.width > {old_width} and c.height > {old_height}')
                coords = lua('local c=client.focus; return (c.x + math.floor(c.width/2))..","..(c.y + 12)')
                x, y = re.search(r'"(\d+),(\d+)"', coords).groups()
                subprocess.run(["xdotool", "mousemove", x, y, "click", "--repeat", "2", "--delay", "100", "1"],
                               env=env, check=True, timeout=3)
                wait('return client.focus and tostring(client.focus.maximized)', '"true"')
                maximum = lua('local c=client.focus; local _,bottom=c:titlebar_bottom(); local a=c.screen.workarea; return c.border_width == 0 and bottom == 0 and c.x == a.x and c.y == a.y and c.width == a.width and c.height == a.height')
                assert 'true' in maximum, lua('local c=client.focus; local _,b=c:titlebar_bottom(); local a=c.screen.workarea; return "border="..c.border_width.." bottom="..b.." c="..c.x..","..c.y..","..c.width..","..c.height.." area="..a.x..","..a.y..","..a.width..","..a.height')
                lua('client.focus.maximized=false')
                assert 'true' in lua('local c=client.focus; local _,b=c:titlebar_bottom(); return c.border_width == 2 and b == 10')
                press('alt+F11')
                wait('return client.focus and tostring(client.focus.fullscreen)', '"true"')
                assert 'true' in lua('local c=client.focus; local a=c.screen.geometry; return c.border_width == 0 and c.x == a.x and c.y == a.y and c.width == a.width and c.height == a.height and not c.screen.panel.visible')
                press('alt+F11')
                wait('return client.focus and tostring(client.focus.fullscreen)', '"false"')
                wait('return tostring(screen[1].panel.visible)', '"true"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeB" then c.fullscreen=true end end')
                wait('return tostring(screen[1].panel.visible)', '"false"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeB" then c:kill() end end')
                wait('return tostring(screen[1].panel.visible)', '"true"')
                press('super+Left')
                assert 'true' in lua('local c=client.focus; return c.x == screen[1].workarea.x and c.y >= 30 and c.width <= 640')
                press('super+d')
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return tostring(c.minimized) end end', '"true"')
                press('super+d')
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return tostring(c.minimized) end end', '"false"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then c:emit_signal("request::activate", "test", {raise=true}) end end')
                press('alt+F4')
                wait('local n=0; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then n=n+1 end end; return n', '0')
                press('super+ctrl+r')
                time.sleep(0.5)
                wait('return #screen[1].tags', '4')
                assert 'true' in lua('return require("awful").layout.get(screen[1]) == require("awful").layout.suit.floating')
                assert "awesome config:" not in logfile.read_text(), logfile.read_text()
                wait('return screen[1].workarea.y', '30')
                assert wm.poll() is None, logfile.read_text()
                press('super+p')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"true"')
                press('Escape')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
                press('super+shift+q')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                press('Escape')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"false"')
                assert wm.poll() is None
                # Exercise the actual Win+L binding and foreground i3lock, only on Xvfb.
                press('super+l')
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline and not lock_pids:
                    candidates = subprocess.run(["pgrep", "-x", "i3lock"], capture_output=True, text=True).stdout.split()
                    for pid in candidates:
                        try:
                            environment = Path(f"/proc/{pid}/environ").read_bytes().split(b'\0')
                            if ("DISPLAY=" + env["DISPLAY"]).encode() in environment:
                                lock_pids.append(int(pid))
                        except (PermissionError, FileNotFoundError):
                            pass
                    time.sleep(0.1)
                assert lock_pids, 'Win+L did not start i3lock on the private display'
                time.sleep(0.3)
                windows = subprocess.run(["xdotool", "search", "--class", "i3lock"], env=env,
                                         capture_output=True, text=True, timeout=3)
                assert windows.returncode == 0 and windows.stdout.strip(), 'i3lock did not map a lock window'
                # A simultaneous xss-lock/Win+L invocation must not launch a second locker.
                duplicate = subprocess.run(["sh", str(helpers / "openbox-lock")], env=env, timeout=3)
                assert duplicate.returncode == 0
                for pid in lock_pids:
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                lock_pids.clear()
                time.sleep(0.5)
                press('super+shift+q')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                press('Escape')
                assert wm.poll() is None, 'Escape from quit confirmation must cancel'
                lua('awesome.quit()')
                assert wm.wait(timeout=5) == 0
                print("PASS: native panel/date/volume, Start/calendar/tray, wallpaper, corner resize, borderless maximize/fullscreen, workspaces, Win+P outputs menu, confirmed Win+Shift+Q, reload and Win+L/i3lock")
        finally:
            for pid in lock_pids:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
